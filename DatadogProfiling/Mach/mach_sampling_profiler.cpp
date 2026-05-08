/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "mach_sampling_profiler.h"
#include "aggregation_worker.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <dlfcn.h>
#include <thread>
#include <chrono>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/thread_info.h>
#include <mach/machine/thread_state.h>
#include <new>

// Address validation constants and macros
//
// These values define the valid range for user-space addresses on 64-bit systems:
//
// MIN_USERSPACE_ADDR (0x1000):
//   - Corresponds to the typical page size (4KB)
//   - Helps avoid null pointer dereference regions (0x0 - 0xFFF)
//   - Based on standard virtual memory layouts where the first page is unmapped
//   - Reference: mach/vm_param.h, typical VM_MIN_ADDRESS values
//
// MAX_USERSPACE_ADDR (0x7FFFFFFFF000ULL):
//   - Upper limit for user-space addresses on 64-bit ARM64/x86_64
//   - On ARM64: user space typically occupies 0x0 - 0x7FFFFFFFF000
//   - On x86_64: similar layout with kernel space starting around 0x8000000000000000
//   - This leaves the upper address space for kernel/system use
//   - Reference: ARM64 memory layout documentation, x86_64 canonical addressing
//
// FRAME_POINTER_ALIGN (8 bytes):
//   - 64-bit systems require 8-byte alignment for pointers
//   - Stack frame pointers must be properly aligned to avoid bus errors
//   - Reference: ARM64/x86_64 ABI specifications

static constexpr uintptr_t MIN_USERSPACE_ADDR = 0x1000ULL;          // 4KB - avoid null deref region
static constexpr uintptr_t MAX_USERSPACE_ADDR = 0x7FFFFFFFF000ULL;  // ~128TB - max user space on 64-bit
static constexpr uintptr_t FRAME_POINTER_ALIGN = 0x7ULL;            // 8-byte alignment mask

// Thread name buffer size
//
// PTHREAD_THREAD_NAME_MAX (64):
//   - Apple OSs do not expose the length limit of the name

static constexpr size_t PTHREAD_THREAD_NAME_MAX = 64;

// Main thread pthread identifier for comparison
static pthread_t g_main_pthread = NULL;

// Safe memory read using signal handling
// Thread-local storage for signal-based safe memory reading
static thread_local sigjmp_buf g_safe_read_handler;
static thread_local volatile sig_atomic_t g_is_safe_read = false;

// Previous signal handlers to restore if needed
static struct sigaction g_prev_sigbus_handler;
static struct sigaction g_prev_sigsegv_handler;

/**
 * Signal handler for catching memory access errors during stack unwinding.
 * If safe_read is active, longjmp back to the safe point.
 * Otherwise, call the previous handler or use default behavior.
 */
static void safe_read_signal_handler(int sig, siginfo_t* info, void* context) {
    // If we're in a safe_read, recover via longjmp
    if (g_is_safe_read) {
        siglongjmp(g_safe_read_handler, 1);
    }
    
    // Not in safe_read - forward to previous handler
    struct sigaction* prev = (sig == SIGBUS) ? &g_prev_sigbus_handler : &g_prev_sigsegv_handler;
    
    if (prev->sa_flags & SA_SIGINFO) {
        if (prev->sa_sigaction) {
            prev->sa_sigaction(sig, info, context);
        }
    } else if (prev->sa_handler == SIG_DFL) {
        // Restore default handler using sigaction (async-signal-safe)
        struct sigaction dfl = {};
        dfl.sa_handler = SIG_DFL;
        sigemptyset(&dfl.sa_mask);
        sigaction(sig, &dfl, nullptr);
        raise(sig);
    } else if (prev->sa_handler != SIG_IGN) {
        prev->sa_handler(sig);
    }
}

/**
 * Sets the main thread pthread identifier.
 *
 * This function should be called from the main thread early in the process lifecycle.
 *
 * @param thread The pthread identifier for the main thread
 */
void set_main_thread(pthread_t thread) {
    g_main_pthread = thread;
}

/**
 * Install signal handlers for safe memory reading.
 */
static void init_safe_read_handlers() {
    static bool initialized = false;
    if (initialized) {
        return;
    }
    initialized = true;

    // Manually install the handler defined in this file
    struct sigaction sa = {};
    sa.sa_sigaction = safe_read_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;

    // Install handlers and save previous ones
    sigaction(SIGBUS, &sa, &g_prev_sigbus_handler);
    sigaction(SIGSEGV, &sa, &g_prev_sigsegv_handler);
}

/**
 * Validates if an address is within reasonable user-space bounds.
 * Rejects null pointers, kernel addresses, and other invalid ranges.
 */
static constexpr bool is_valid_userspace_addr(uintptr_t addr) {
    return addr >= MIN_USERSPACE_ADDR && addr <= MAX_USERSPACE_ADDR;
}

/**
 * Validates if a frame pointer is valid: within user-space bounds and properly aligned.
 * Frame pointers must be 8-byte aligned on 64-bit systems.
 */
static constexpr bool is_valid_frame_pointer(uintptr_t fp) {
    return is_valid_userspace_addr(fp) && (fp & FRAME_POINTER_ALIGN) == 0;
}

/**
 * Initializes a stack trace with allocated frames.
 * 
 * @param trace Pointer to stack trace to initialize
 * @param max_depth Maximum number of frames to allocate
 * @param interval_nanos The actual sampling interval in nanoseconds for this sample
 * @return true if initialization succeeded, false on allocation failure
 */
bool stack_trace_init(stack_trace_t* trace, uint32_t max_depth, uint64_t interval_nanos) {
    if (!trace) return false;
    trace->tid = 0;
    trace->thread_name = nullptr;
    trace->timestamp = 0;
    trace->sampling_interval_nanos = interval_nanos;
    trace->cpu_time_nanos = 0;
    trace->frame_count = 0;
    trace->frames = (stack_frame_t*)malloc(max_depth * sizeof(stack_frame_t));
    return trace->frames != nullptr;
}

static bool thread_cpu_time_nanos(thread_t thread, uint64_t* cpu_time_nanos) {
    if (!cpu_time_nanos) return false;

    thread_basic_info_data_t info{};
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info(thread, THREAD_BASIC_INFO, reinterpret_cast<thread_info_t>(&info), &count) != KERN_SUCCESS) {
        return false;
    }

    const uint64_t user_time_nanos =
        (static_cast<uint64_t>(info.user_time.seconds) * 1000000000ULL)
        + (static_cast<uint64_t>(info.user_time.microseconds) * 1000ULL);
    const uint64_t system_time_nanos =
        (static_cast<uint64_t>(info.system_time.seconds) * 1000000000ULL)
        + (static_cast<uint64_t>(info.system_time.microseconds) * 1000ULL);

    *cpu_time_nanos = user_time_nanos + system_time_nanos;
    return true;
}

/**
 * Destroys a stack trace, freeing the thread name and frames array.
 * 
 * @param trace Pointer to stack trace to clean up (can be nullptr)
 */
void stack_trace_destroy(stack_trace_t* trace) {
    if (!trace) return;

    // Free thread name if allocated
    if (trace->thread_name) {
        free((void*)trace->thread_name);
        trace->thread_name = nullptr;
    }
    
    if (trace->frames) {
        free(trace->frames);
        trace->frames = nullptr;
    }
}

/**
 * Gets thread state and extracts frame pointer and program counter.
 *
 * @param thread The thread to get the state from
 * @param fp Output parameter for frame pointer
 * @param pc Output parameter for program counter
 * @return true if successful, false if thread state could not be retrieved
 */
bool thread_get_frame_pointers(thread_t thread, void** fp, void** pc) {
#if defined(__x86_64__)
    x86_thread_state64_t state;
    mach_msg_type_number_t count = x86_THREAD_STATE64_COUNT;
    if (thread_get_state(thread, x86_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        *fp = (void*)state.__rbp;
        *pc = (void*)state.__rip;
        return true;
    }
#elif defined(__i386__)
    x86_thread_state32_t state;
    mach_msg_type_number_t count = x86_THREAD_STATE32_COUNT;
    if (thread_get_state(thread, x86_THREAD_STATE32, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        *fp = (void*)state.__ebp;
        *pc = (void*)state.__eip;
        return true;
    }
#elif defined(__arm64__)
    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        *fp = (void*)arm_thread_state64_get_fp(state);
        *pc = (void*)arm_thread_state64_get_pc(state);
        return true;
    }
#elif defined(__arm__)
    arm_thread_state32_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE32_COUNT;
    if (thread_get_state(thread, ARM_THREAD_STATE32, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        // https://developer.apple.com/documentation/xcode/writing-armv6-code-for-ios#//apple_ref/doc/uid/TP40009021-SW1
        *fp = (void*)state.__r[7];  // R7 is commonly used as frame pointer on iOS
        *pc = (void*)state.__pc;
        return true;
    }
#endif
    return false;
}

/**
 * Fills thread information (TID and name) for a stack trace.
 * Safe to call outside critical sections.
 *
 * @param trace Stack trace to fill with thread info
 * @param thread The mach thread to get info from
 * @return true if thread info was successfully retrieved
 */
bool stack_trace_get_thread_info(stack_trace_t* trace, thread_t thread) {
    if (!trace) return false;
    
    trace->tid = thread;
    trace->thread_name = nullptr;
    
    pthread_t pthread = pthread_from_mach_thread_np(thread);
    if (!pthread) return false;

    // Allocate buffer and get thread name
    trace->thread_name = (char*)malloc(PTHREAD_THREAD_NAME_MAX);
    if (!trace->thread_name) return false;
    
    int result = pthread_getname_np(pthread, (char*)trace->thread_name, PTHREAD_THREAD_NAME_MAX);

    if (pthread == g_main_pthread) {
        strlcpy((char*)trace->thread_name, "com.apple.main-thread", PTHREAD_THREAD_NAME_MAX);
    }
    
    if (result == KERN_SUCCESS) return true;
    
    free((void*)trace->thread_name);
    trace->thread_name = nullptr;
    return false;
}

/**
 * Safely reads memory from a potentially invalid address.
 *
 * If memory is invalid, SIGBUS/SIGSEGV is caught and we return false.
*/
bool safe_read_memory(void* addr, void* buffer, size_t size) {
    // Set up the JUMP TARGET
    if (sigsetjmp(g_safe_read_handler, 1) == 0) {
        g_is_safe_read = true;
        // try direct memory copy
        memcpy(buffer, addr, size);
        g_is_safe_read = false;
        return true;
    }

    // Memory access failed
    // We land here if safe_read_signal_handler() called siglongjmp()
    g_is_safe_read = false;
    return false;
}

/**
 * Samples a thread's stack to collect stack trace information.
 *
 * @param trace Pre-allocated stack trace to fill
 * @param thread The thread to sample
 * @param max_depth Maximum number of frames to capture
 */
void stack_trace_sample_thread(stack_trace_t* trace, thread_t thread, uint32_t max_depth) {
    trace->timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    trace->frame_count = 0;

    void *fp = nullptr;
    void *pc = nullptr;
    if (!thread_get_frame_pointers(thread, &fp, &pc)) return;

    while (trace->frame_count < max_depth && pc != nullptr) {
        auto& frame = trace->frames[trace->frame_count];
        frame.instruction_ptr = (uint64_t)pc;
        // Keep raw traces safe for callbacks by setting safe defaults
        frame.image.load_address = 0;
        memset(frame.image.uuid, 0, sizeof(uuid_t));
        frame.image.filename = nullptr;

        trace->frame_count++;
        
        if (fp == nullptr) break;
        // Validate frame pointer before dereferencing
        if (!is_valid_frame_pointer((uintptr_t)fp)) break;

        // Read the next frame pointer and return address
        void* next_frame[2];
        if (!safe_read_memory(fp, static_cast<void*>(next_frame), sizeof(next_frame))) break;

        fp = next_frame[0];  // Next frame pointer
        pc = next_frame[1];  // Return address

        // Validate the new PC
        if (!is_valid_userspace_addr((uintptr_t)pc)) break;
    }
}

namespace dd::profiler {

/**
 * Constructs a profiler instance.
 *
 * @param config The sampling configuration to use
 * @param callback Function to call with collected stack traces
 * @param ctx Context to pass to the callback
 */
mach_sampling_profiler::mach_sampling_profiler(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* ctx,
    uint64_t hard_limit_bytes)
    : should_sample(false)
    , config(SAMPLING_CONFIG_DEFAULT)
    , callback(callback)
    , ctx(ctx) {
    if (config) this->config = *config;
    sample_buffer.reserve(this->config.max_buffer_size);
    worker.reset(new (std::nothrow) aggregation_worker(
        this->config.max_buffer_size,
        this->config.max_stack_depth,
        callback,
        ctx,
        hard_limit_bytes,
        this->config.qos_class
    ));
}

/**
 * Destructor that ensures sampling is stopped.
 */
mach_sampling_profiler::~mach_sampling_profiler() {
    stop_sampling();
}

/**
 * Static entry point for the sampling thread.
 */
void* mach_sampling_profiler::sampling_thread_entry(void* arg) {
    pthread_setname_np("com.datadoghq.profiler.sampling");
    auto* profiler = static_cast<mach_sampling_profiler*>(arg);
    profiler->sampling_thread_mach.store(
        pthread_mach_thread_np(pthread_self()),
        std::memory_order_relaxed
    );
    profiler->main();
    return nullptr;
}

/**
 * Starts the sampling process.
 * Thread-safe: protected by mutex.
 *
 * @return true if sampling was started successfully
 */
bool mach_sampling_profiler::start_sampling() {
    std::lock_guard<std::mutex> lock(state_mutex);

    if (should_sample.load(std::memory_order_relaxed)
        || has_sampling_thread.load(std::memory_order_relaxed)) return false;

    if (config.profile_current_thread_only) {
        target_thread = pthread_self();
    }

    // Clear any leftover data from previous runs
    sample_buffer.clear();
    previous_thread_cpu_time_nanos.clear();
    if (sample_buffer.capacity() < config.max_buffer_size) {
        sample_buffer.reserve(config.max_buffer_size);
    }
    sampling_thread_mach.store(MACH_PORT_NULL, std::memory_order_relaxed);

    init_safe_read_handlers();
    if (!worker || !worker->start()) {
        return false;
    }

    should_sample.store(true, std::memory_order_relaxed);

    pthread_attr_t sampling_attr;
    pthread_attr_init(&sampling_attr);
    pthread_attr_set_qos_class_np(&sampling_attr, config.qos_class, 0);

    int sampling_result = pthread_create(&sampling_thread, &sampling_attr, sampling_thread_entry, this);
    pthread_attr_destroy(&sampling_attr);
    if (sampling_result != 0) {
        should_sample.store(false, std::memory_order_relaxed);
        worker->stop();
        return false;
    }

    has_sampling_thread.store(true, std::memory_order_release);
    return true;
}

/**
 * Stops the sampling process.
 *
 * If called from a thread owned by this profiler, this only requests an
 * asynchronous stop. Full join and reset are performed later by another thread.
 *
 */
void mach_sampling_profiler::stop_sampling() {
    if ((has_sampling_thread.load(std::memory_order_acquire) && pthread_equal(pthread_self(), sampling_thread))
        || (worker && worker->is_worker_thread())) {
        request_stop();
        return;
    }

    std::lock_guard<std::mutex> lock(state_mutex);
    request_stop();

    // Join while holding the lock to ensure the previous session is fully drained
    // before any new session can start.
    if (has_sampling_thread.load(std::memory_order_acquire)) {
        pthread_join(sampling_thread, nullptr);
        sampling_thread_mach.store(MACH_PORT_NULL, std::memory_order_relaxed);
        has_sampling_thread.store(false, std::memory_order_release);
    }

    if (worker) {
        worker->stop();
    }
}

void mach_sampling_profiler::request_flush(flush_action_t action, void* action_ctx) {
    if (worker) {
        worker->request_flush(action, action_ctx);
    }
}

void mach_sampling_profiler::request_stop() {
    should_sample.store(false, std::memory_order_relaxed);
}

void mach_sampling_profiler::consume_diagnostics(dd_profiler_diagnostics_t* out) {
    if (worker) {
        worker->consume_diagnostics(out);
    } else if (out) {
        out->dropped_batch_count = 0;
        out->dropped_sample_count = 0;
        out->max_pending_bytes = 0;
    }
}

bool mach_sampling_profiler::is_profiler_internal_thread(thread_t thread) const {
    const thread_t sampling_thread_id = sampling_thread_mach.load(std::memory_order_relaxed);
    if (sampling_thread_id != MACH_PORT_NULL && thread == sampling_thread_id) {
        return true;
    }

    return worker && worker->is_worker_thread(thread);
}

/**
 * Samples a single thread's stack.
 *
 * @param thread The thread to sample
 * @param interval_nanos The actual sampling interval in nanoseconds for this sample
 */
void mach_sampling_profiler::sample_thread(thread_t thread, uint64_t interval_nanos, uint64_t cpu_time_nanos) {
    stack_trace_t trace;
    if (!stack_trace_init(&trace, config.max_stack_depth, interval_nanos)) return;
    trace.cpu_time_nanos = cpu_time_nanos;

    // Get thread info
    stack_trace_get_thread_info(&trace, thread);

    if (thread_suspend(thread) == KERN_SUCCESS) {
        // CRITICAL: Thread is suspended - avoid operations that could deadlock
        //
        // The suspended thread may be holding system locks (memory allocator, pthread, etc).
        // If we try to acquire these same locks while the thread is suspended, we'll deadlock.
        //
        // Specifically avoid:
        // - Memory allocations (new, malloc) - memory allocator locks
        // - System calls that acquire locks - they may be held by suspended thread
        // - pthread functions - they share locks with system APIs
        stack_trace_sample_thread(&trace, thread, config.max_stack_depth);
        thread_resume(thread);
    }

    if (trace.frame_count > 0) {
        sample_buffer.push_back(trace);
    } else {
        stack_trace_destroy(&trace);
    }
}

uint64_t mach_sampling_profiler::thread_cpu_time_delta_nanos(thread_t thread) {
    if (!config.record_cpu_time) {
        return 0;
    }

    uint64_t current_cpu_time_nanos = 0;
    if (!thread_cpu_time_nanos(thread, &current_cpu_time_nanos)) {
        return 0;
    }

    auto result = previous_thread_cpu_time_nanos.emplace(thread, current_cpu_time_nanos);
    if (result.second) {
        return 0;
    }

    const uint64_t previous_cpu_time_nanos = result.first->second;
    result.first->second = current_cpu_time_nanos;

    if (current_cpu_time_nanos < previous_cpu_time_nanos) {
        return 0;
    }

    return current_cpu_time_nanos - previous_cpu_time_nanos;
}

void mach_sampling_profiler::prune_thread_cpu_time_state(const thread_t* threads, mach_msg_type_number_t count) {
    if (!config.record_cpu_time || previous_thread_cpu_time_nanos.empty()) {
        return;
    }

    for (auto it = previous_thread_cpu_time_nanos.begin(); it != previous_thread_cpu_time_nanos.end();) {
        bool is_live_thread = false;
        for (mach_msg_type_number_t i = 0; i < count; i++) {
            if (threads[i] == it->first) {
                is_live_thread = true;
                break;
            }
        }

        if (is_live_thread) {
            ++it;
        } else {
            it = previous_thread_cpu_time_nanos.erase(it);
        }
    }
}

/**
 * Main sampling loop that collects stack traces from threads.
 */
void mach_sampling_profiler::main() {
    while (should_sample.load(std::memory_order_relaxed)) {
        // Check for flush request at a safe point (no threads suspended).
        worker->service_pending_flush_request(sample_buffer);

        // Sampling interval in nanoseconds
        uint64_t interval_nanos = config.sampling_interval_nanos;

        if (sample_buffer.size() >= config.max_buffer_size) {
            worker->enqueue_active_buffer(sample_buffer);
        }

        if (config.profile_current_thread_only) {
            const thread_t thread = pthread_mach_thread_np(target_thread);
            sample_thread(thread, interval_nanos, thread_cpu_time_delta_nanos(thread));
            if (sample_buffer.size() >= config.max_buffer_size) {
                worker->enqueue_active_buffer(sample_buffer);
            }
        } else {
            thread_act_array_t threads = nullptr;
            mach_msg_type_number_t count = 0;
            
            if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
                continue;
            }

            for (mach_msg_type_number_t i = 0; i < count; i++) {
                if (!should_sample.load(std::memory_order_relaxed)) break;

                // Stop sampling if we've reached the configured thread limit
                if (config.max_thread_count != 0 && i > config.max_thread_count) break;

                // Skip profiler-owned threads to avoid self-noise in customer profiles.
                if (is_profiler_internal_thread(threads[i])) continue;
                
                sample_thread(threads[i], interval_nanos, thread_cpu_time_delta_nanos(threads[i]));

                if (sample_buffer.size() >= config.max_buffer_size) {
                    worker->enqueue_active_buffer(sample_buffer);
                }
            }

            prune_thread_cpu_time_state(threads, count);

            // Clean up thread references
            for (mach_msg_type_number_t i = 0; i < count; i++) {
                mach_port_deallocate(mach_task_self(), threads[i]);
            }

            vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t));
        }

        // Sleep for the same interval we recorded
        std::this_thread::sleep_for(std::chrono::nanoseconds(interval_nanos));
    }

    // Final safe point: hand off any remaining samples and complete a pending flush.
    worker->finish_producer(sample_buffer);
}

} // namespace dd::profiler

extern "C" {

void safe_read_memory_for_testing(void* addr, void* buffer, size_t size) {
    safe_read_memory(addr, buffer, size);
}

void init_safe_read_handlers_for_testing(void) {
    init_safe_read_handlers();
}

} // extern "C"

#endif // __APPLE__ && !TARGET_OS_WATCH
