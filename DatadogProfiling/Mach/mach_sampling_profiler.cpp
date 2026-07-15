/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "mach_sampling_profiler.h"
#include "aggregation_worker.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <dlfcn.h>
#include <algorithm>
#include <thread>
#include <chrono>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/machine/thread_state.h>
#include <new>
#include <utility>
#include <mach/vm_map.h>

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

// Hard upper bound for the stack region read per thread sample.
// The actual bytes requested are computed dynamically from the thread's SP and FP,
// so this cap is only hit by threads with unusually large frames or very deep stacks.
static constexpr size_t STACK_REGION_MAX_READ = 65536; // 64 KB safety cap

// Conservative per-frame size estimate used to compute the dynamic read size.
// ARM64/x86_64 frames range from 16 bytes (leaf) to ~512 bytes (heavy locals).
// 128 bytes covers the vast majority of real-world frames without over-reading.
static constexpr size_t STACK_REGION_FRAME_SIZE_ESTIMATE = 128;

struct frame_pointer_pair_t {
    void* next_frame_pointer;
    void* return_address;
};

static_assert(sizeof(frame_pointer_pair_t) == sizeof(void*) * 2, "Frame pointer pair must stay two pointers.");

// Main thread pthread identifier for comparison
static pthread_t g_main_pthread = NULL;

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
 * Reads a contiguous region of the calling task's virtual memory.
 * Uses vm_read_overwrite which returns an error code for unmapped/invalid addresses
 * instead of raising EXC_BAD_ACCESS, making it safe to call with partially-valid
 * thread stacks and compatible with Mach exception handlers such as Crashlytics.
 *
 * @param addr  Starting address.
 * @param buf   Caller-supplied output buffer.
 * @param size  Maximum bytes to read (buf must be at least this large).
 * @return Bytes actually read, 0 on any failure.
 */
static size_t read_memory_region(void* addr, uint8_t* buf, size_t size) {
    if (addr == nullptr || buf == nullptr || size == 0) {
        return 0;
    }

    const uintptr_t address = reinterpret_cast<uintptr_t>(addr);
    const uintptr_t buffer = reinterpret_cast<uintptr_t>(buf);
    if (address > UINTPTR_MAX - size || buffer > UINTPTR_MAX - size) {
        return 0;
    }

    vm_size_t read_size = static_cast<vm_size_t>(size);
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        reinterpret_cast<vm_address_t>(addr),
        static_cast<vm_size_t>(size),
        reinterpret_cast<vm_address_t>(buf),
        &read_size
    );
    return (kr == KERN_SUCCESS && read_size == size) ? static_cast<size_t>(read_size) : 0;
}

/**
 * Reads as much of a stack region as possible by walking page boundaries.
 *
 * This is only used as a fallback when the full-region read fails. Reading from
 * SP upward preserves a contiguous prefix of the stack and stops at the first
 * unreadable page, so the frame walker can still salvage frames already copied.
 */
static size_t read_stack_region_by_pages(void* sp, uint8_t* buf, size_t size) {
    if (sp == nullptr || buf == nullptr || size == 0 || vm_page_size == 0) {
        return 0;
    }

    uintptr_t current_address = reinterpret_cast<uintptr_t>(sp);
    size_t total_read = 0;
    const size_t page_size = static_cast<size_t>(vm_page_size);

    while (total_read < size) {
        const size_t page_offset = current_address % page_size;
        const size_t bytes_until_page_end = page_size - page_offset;
        const size_t bytes_remaining = size - total_read;
        const size_t chunk_size = std::min(bytes_remaining, bytes_until_page_end);

        const size_t bytes_read = read_memory_region(
            reinterpret_cast<void*>(current_address),
            buf + total_read,
            chunk_size
        );

        if (bytes_read != chunk_size) {
            break;
        }

        total_read += bytes_read;
        if (total_read == size) {
            break;
        }

        current_address += bytes_read;
    }

    return total_read;
}

/**
 * Reads a stack region with a fast full-region read and a page-by-page fallback.
 *
 * The common path is one vm_read_overwrite per sampled thread. If that all-or-
 * nothing read fails because a later page is unmapped, the fallback returns the
 * contiguous readable prefix from SP so the sample is degraded rather than lost.
 */
static size_t read_stack_region(void* sp, uint8_t* buf, size_t size) {
    const size_t bytes_read = read_memory_region(sp, buf, size);
    if (bytes_read == size) {
        return bytes_read;
    }

    return read_stack_region_by_pages(sp, buf, size);
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
    trace->frame_count = 0;
    trace->frames = (stack_frame_t*)malloc(max_depth * sizeof(stack_frame_t));
    return trace->frames != nullptr;
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
 * Gets thread state and extracts stack pointer, frame pointer, and program counter.
 * sp is needed to anchor the batch stack read; fp and pc seed the frame walk.
 *
 * @param thread The thread to get the state from (must be suspended)
 * @param fp Output parameter for frame pointer
 * @param pc Output parameter for program counter
 * @param sp Output parameter for stack pointer
 * @return true if successful, false if thread state could not be retrieved
 */
bool thread_get_frame_pointers(thread_t thread, void** fp, void** pc, void** sp) {
#if defined(__x86_64__)
    x86_thread_state64_t state;
    mach_msg_type_number_t count = x86_THREAD_STATE64_COUNT;
    if (thread_get_state(thread, x86_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        *fp = (void*)state.__rbp;
        *pc = (void*)state.__rip;
        *sp = (void*)state.__rsp;
        return true;
    }
#elif defined(__i386__)
    x86_thread_state32_t state;
    mach_msg_type_number_t count = x86_THREAD_STATE32_COUNT;
    if (thread_get_state(thread, x86_THREAD_STATE32, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        *fp = (void*)state.__ebp;
        *pc = (void*)state.__eip;
        *sp = (void*)state.__esp;
        return true;
    }
#elif defined(__arm64__)
    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        *fp = (void*)arm_thread_state64_get_fp(state);
        *pc = (void*)arm_thread_state64_get_pc(state);
        *sp = (void*)arm_thread_state64_get_sp(state);
        return true;
    }
#elif defined(__arm__)
    arm_thread_state32_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE32_COUNT;
    if (thread_get_state(thread, ARM_THREAD_STATE32, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        // https://developer.apple.com/documentation/xcode/writing-armv6-code-for-ios#//apple_ref/doc/uid/TP40009021-SW1
        *fp = (void*)state.__r[7];  // R7 is commonly used as frame pointer on iOS
        *pc = (void*)state.__pc;
        *sp = (void*)state.__sp;
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
 * Reads a saved frame pointer / program counter pair from a stack snapshot.
 */
static bool read_frame_pair_from_snapshot(
    uintptr_t fp,
    uintptr_t stack_base,
    const uint8_t* stack_buf,
    size_t bytes_read,
    frame_pointer_pair_t* next_frame
) {
    if (stack_base == 0 || stack_buf == nullptr || bytes_read < sizeof(frame_pointer_pair_t) || fp < stack_base) {
        return false;
    }

    const uintptr_t fp_offset = fp - stack_base;
    if (fp_offset > bytes_read - sizeof(frame_pointer_pair_t)) {
        return false;
    }

    memcpy(static_cast<void*>(next_frame), stack_buf + fp_offset, sizeof(frame_pointer_pair_t));
    return true;
}

/**
 * Reads a saved frame pointer / program counter pair directly from memory.
 *
 * This is only used when a valid frame pointer falls outside the initial stack
 * snapshot. It preserves stack accuracy for large frames without returning to
 * faulting memory reads; vm_read_overwrite reports failure instead of crashing.
 */
static bool read_frame_pair_from_memory(uintptr_t fp, frame_pointer_pair_t* next_frame) {
    return read_memory_region(
        reinterpret_cast<void*>(fp),
        reinterpret_cast<uint8_t*>(next_frame),
        sizeof(frame_pointer_pair_t)
    ) == sizeof(frame_pointer_pair_t);
}

/**
 * Walks a frame pointer chain from a pre-populated local buffer.
 *
 * If allow_memory_fallback is true, a valid frame pointer outside the copied
 * region is read with vm_read_overwrite so unusually large frames can still be
 * followed safely. The common path remains local-buffer reads with no syscalls.
 */
static void walk_frames(
    stack_trace_t* trace,
    void* initial_fp,
    void* initial_pc,
    uintptr_t stack_base,
    const uint8_t* stack_buf,
    size_t bytes_read,
    uint32_t max_depth,
    bool allow_memory_fallback
) {
    void* fp = initial_fp;
    void* pc = initial_pc;
    trace->frame_count = 0;

    while (trace->frame_count < max_depth && pc != nullptr) {
        auto& frame = trace->frames[trace->frame_count];
        frame.instruction_ptr = (uint64_t)pc;
        frame.image.load_address = 0;
        memset(frame.image.uuid, 0, sizeof(uuid_t));
        frame.image.filename = nullptr;
        trace->frame_count++;

        const uintptr_t fp_addr = reinterpret_cast<uintptr_t>(fp);
        if (!is_valid_frame_pointer(fp_addr)) break;

        // Frame pointers grow toward higher addresses (stack grows down),
        // so fp must be at or above sp when a stack snapshot is available.
        if (stack_base != 0 && fp_addr < stack_base) break;

        frame_pointer_pair_t next_frame = {};
        if (!read_frame_pair_from_snapshot(fp_addr, stack_base, stack_buf, bytes_read, &next_frame)) {
            if (!allow_memory_fallback || !read_frame_pair_from_memory(fp_addr, &next_frame)) {
                break;
            }
        }

        fp = next_frame.next_frame_pointer;  // saved x29 / rbp
        pc = next_frame.return_address;  // saved lr / return address on stack

        if (!is_valid_userspace_addr(reinterpret_cast<uintptr_t>(pc))) break;
    }
}

/**
 * Walks a frame pointer chain entirely from a pre-populated local buffer.
 *
 * Resets trace->frame_count to 0, records initial_pc as the first frame, then
 * follows the frame pointer chain by reading saved (fp, pc) word pairs from
 * stack_buf with bounds checks. The walk stops on: max_depth reached, invalid
 * FP/PC, FP outside the captured region, or null PC.
 *
 * No syscalls and no memory accesses outside [stack_buf, stack_buf + bytes_read)
 * are performed, so this function cannot raise EXC_BAD_ACCESS or fault.
 *
 * Exposed via safe_read_testing.h so tests can exercise the bounds-check guards
 * and cycle-termination behavior directly with crafted buffers.
 *
 * @param trace        Pre-allocated trace; trace->frames must point to at least
 *                     max_depth entries.
 * @param initial_fp   First frame pointer to walk from.
 * @param initial_pc   First program counter to record.
 * @param stack_base   Base address that stack_buf was read from.
 * @param stack_buf    Buffer containing a snapshot of stack memory.
 * @param bytes_read   Valid bytes in stack_buf.
 * @param max_depth    Hard cap on frames to record.
 */
extern "C" void walk_frames_in_buffer(
    stack_trace_t* trace,
    void* initial_fp,
    void* initial_pc,
    uintptr_t stack_base,
    const uint8_t* stack_buf,
    size_t bytes_read,
    uint32_t max_depth
) {
    walk_frames(trace, initial_fp, initial_pc, stack_base, stack_buf, bytes_read, max_depth, false);
}

extern "C" void walk_frames_with_safe_read_fallback_for_testing(
    stack_trace_t* trace,
    void* initial_fp,
    void* initial_pc,
    uintptr_t stack_base,
    const uint8_t* stack_buf,
    size_t bytes_read,
    uint32_t max_depth
) {
    walk_frames(trace, initial_fp, initial_pc, stack_base, stack_buf, bytes_read, max_depth, true);
}

/**
 * Samples a thread's stack to collect stack trace information.
 *
 * Reads the thread's live stack region with a single vm_read_overwrite call, then
 * walks frame pointers from the local copy. If a valid frame pointer lands outside
 * the initial copy (for example because of a large stack allocation), that one
 * saved FP/PC pair is read with vm_read_overwrite as a safe fallback. This avoids
 * faulting memory reads while keeping the sampled stack internally consistent.
 *
 * Overhead: one vm_read_overwrite per thread sample on the common path, with extra
 * safe reads only for out-of-window frame pointers.
 *
 * @param trace Pre-allocated stack trace to fill
 * @param thread The thread to sample (must already be suspended)
 * @param max_depth Maximum number of frames to capture
 */
static void stack_trace_sample_thread(
    stack_trace_t* trace,
    thread_t thread,
    uint32_t max_depth
) {
    trace->frame_count = 0;

    void* fp = nullptr;
    void* pc = nullptr;
    void* sp = nullptr;
    if (!thread_get_frame_pointers(thread, &fp, &pc, &sp)) return;

    // Compute the minimum region that covers all frames we intend to walk.
    //
    // The stack grows downward: SP is the lowest live address, FP is above SP
    // (within the current frame), and each subsequent frame pointer is higher still.
    // Reading [SP, SP + region_size] therefore covers the entire walk.
    //
    //   region_size = (FP - SP)               // current frame
    //               + max_depth * frame_est   // remaining frames above FP
    //
    // This is capped at STACK_REGION_MAX_READ as a safety bound for unusual stacks.
    // Compared to always reading 64 KB, this typically reads 8-20 KB instead,
    // reducing data movement by ~4-8x at the default depth of 128.
    alignas(void*) uint8_t stack_buf[STACK_REGION_MAX_READ];
    size_t bytes_read = 0;
    uintptr_t stack_base = 0;

    if (is_valid_userspace_addr(reinterpret_cast<uintptr_t>(sp))) {
        stack_base = reinterpret_cast<uintptr_t>(sp);

        const uintptr_t fp_addr = reinterpret_cast<uintptr_t>(fp);
        const size_t current_frame_size = (fp_addr > stack_base) ? (fp_addr - stack_base) : 0;
        const size_t region_size = std::min(
            current_frame_size + (static_cast<size_t>(max_depth) * STACK_REGION_FRAME_SIZE_ESTIMATE),
            STACK_REGION_MAX_READ
        );

        bytes_read = read_stack_region(sp, stack_buf, region_size);
    }

    walk_frames(trace, fp, pc, stack_base, stack_buf, bytes_read, max_depth, true);
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
    if (sample_buffer.capacity() < config.max_buffer_size) {
        sample_buffer.reserve(config.max_buffer_size);
    }
    sampling_thread_mach.store(MACH_PORT_NULL, std::memory_order_relaxed);

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

bool mach_sampling_profiler::request_flush(flush_action_t action) {
    if (worker) {
        return worker->request_flush(std::move(action));
    }

    return false;
}

void mach_sampling_profiler::request_stop() {
    should_sample.store(false, std::memory_order_relaxed);
}

void mach_sampling_profiler::consume_diagnostics(dd_profiler_diagnostics_t& out) {
    if (worker) {
        worker->consume_diagnostics(out);
    } else {
        out.dropped_batch_count = 0;
        out.dropped_sample_count = 0;
        out.max_pending_bytes = 0;
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
void mach_sampling_profiler::sample_thread(thread_t thread, uint64_t interval_nanos) {
    stack_trace_t trace;
    if (!stack_trace_init(&trace, config.max_stack_depth, interval_nanos)) return;

    // Get thread info
    stack_trace_get_thread_info(&trace, thread);

    trace.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);

    if (thread_suspend(thread) == KERN_SUCCESS) {
        // CRITICAL: Thread is suspended - avoid operations that could deadlock
        //
        // The suspended thread may be holding system locks (memory allocator, pthread, etc).
        // If we try to acquire these same locks while the thread is suspended, we'll deadlock.
        //
        // Specifically avoid nonessential:
        // - Memory allocations (new, malloc) - memory allocator locks
        // - System calls - they may acquire locks held by the suspended thread
        // - pthread functions - they share locks with system APIs
        //
        // Keep this window to the minimum required call-stack capture. The stack
        // memory reads below intentionally use vm_read_overwrite while suspended
        // to keep FP/PC/SP and caller frames from the same execution instant.
        // Work that is not needed for stack consistency must stay outside this
        // section.
        stack_trace_sample_thread(&trace, thread, config.max_stack_depth);
        thread_resume(thread);
    }

    if (trace.frame_count > 0) {
        sample_buffer.push_back(trace);
    } else {
        stack_trace_destroy(&trace);
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
            sample_thread(pthread_mach_thread_np(target_thread), interval_nanos);
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
                
                sample_thread(threads[i], interval_nanos);

                if (sample_buffer.size() >= config.max_buffer_size) {
                    worker->enqueue_active_buffer(sample_buffer);
                }
            }

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

/**
 * Reads a stack region for testing purposes. See read_stack_region for semantics.
 * Returns the number of bytes actually read, 0 on failure.
 */
size_t read_stack_region_for_testing(void* sp, void* buf, size_t buf_size) {
    return read_stack_region(sp, static_cast<uint8_t*>(buf), buf_size);
}

} // extern "C"

#endif // __APPLE__ && !TARGET_OS_WATCH
