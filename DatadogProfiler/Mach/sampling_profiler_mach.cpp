#include "sampling_profiler_mach.h"

#ifdef __APPLE__

#include <dlfcn.h>
#include <thread>
#include <mach/mach_time.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/machine/thread_state.h>
#include <mach-o/loader.h>
#include <algorithm>

namespace dd {
namespace profiler {

/**
 * Retrieves the current state of a thread.
 *
 * @param thread The thread to get the state from
 * @param state Output parameter to store the thread state
 * @return true if successful, false if thread state could not be retrieved
 */
bool get_thread_state(thread_t thread, thread_state_t& state) {
    mach_msg_type_number_t count;

#if defined (__i386__) || defined(__x86_64__)
    count = x86_THREAD_STATE64_COUNT;
    if (thread_get_state(thread, x86_THREAD_STATE64, (thread_state_t)&state, &count) != KERN_SUCCESS) {
        return false;
    }
#elif defined (__arm__) || defined (__arm64__)
    count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count) != KERN_SUCCESS) {
        return false;
    }
#else
    return false;
#endif
    return true;
}

/**
 * Extracts frame pointer and program counter from thread state.
 *
 * @param state The thread state to extract from
 * @param fp Output parameter for frame pointer
 * @param pc Output parameter for program counter
 */
void get_frame_pointers(const thread_state_t& state, void** fp, void** pc) {
#if defined (__i386__) || defined(__x86_64__)
    x86_thread_state64_t* x86_state = (x86_thread_state64_t*)&state;
    *fp = (void*)x86_state->__rbp;
    *pc = (void*)x86_state->__rip;
#elif defined (__arm__) || defined (__arm64__)
    arm_thread_state64_t* arm_state = (arm_thread_state64_t*)&state;
    *fp = (void*)arm_thread_state64_get_fp(*arm_state);
    *pc = (void*)arm_thread_state64_get_pc(*arm_state);
#endif
}

/**
 * Processes a Mach-O header to extract image binary information.
 *
 * @param header The Mach-O header to process
 * @param frame The stack frame to update with image binary information
 */
void get_image_info(const struct mach_header_64* header, stack_frame_t& frame) {
    if (header->magic != MH_MAGIC_64) return;

    const struct load_command* cmd = (const struct load_command*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        switch (cmd->cmd) {
            case LC_SEGMENT_64: {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                frame.binary_size = std::max(frame.binary_size, seg->vmaddr + seg->vmsize);
                break;
            }
            case LC_UUID: {
                const struct uuid_command* uuid_cmd = (const struct uuid_command*)cmd;
                memcpy(frame.uuid, uuid_cmd->uuid, sizeof(uuid_t));
                break;
            }
        }
        cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
    }
}

/**
 * Gets symbol information for a program counter address.
 *
 * @param pc The program counter address to get symbol info for
 * @param frame The stack frame to update with symbol information
 */
void get_symbol_info(void* pc, stack_frame_t& frame) {
    Dl_info info;
    if (!dladdr(pc, &info)) return;

    frame.load_address = (uint64_t)info.dli_fbase;
    strcpy(frame.binary_name, info.dli_fname);
    get_image_info((const struct mach_header_64*)info.dli_fbase, frame); // <-- works for 64-bit only
}

/**
 * Walks the stack of a thread to collect stack trace information.
 *
 * @param thread The thread to walk the stack of
 * @param config The sampling configuration to use
 * @return A stack trace containing frame information
 */
stack_trace_t walk_stack(thread_t thread) {
    stack_trace_t trace = {};
    trace.tid = thread;
    trace.timestamp = mach_absolute_time();
    
    stack_frame_t frames[MAX_STACK_DEPTH];
    trace.frames = frames;
    trace.frame_count = 0;

    thread_state_t state;
    if (!get_thread_state(thread, state)) {
        return trace;
    }

    void* fp = nullptr;
    void* pc = nullptr;
    get_frame_pointers(state, &fp, &pc);

    while (trace.frame_count < MAX_STACK_DEPTH && pc != nullptr) {
        auto& frame = frames[trace.frame_count];
        frame.instruction_ptr = (uint64_t)pc;
        get_symbol_info(pc, frame);

        if (fp == nullptr) break;
        pc = *(void**)fp;
        fp = *(void**)fp;
        trace.frame_count++;
    }
    return trace;
}

/**
 * Constructs a profiler instance.
 *
 * @param config The sampling configuration to use
 * @param callback Function to call with collected stack traces
 * @param user_data User data to pass to the callback
 */
profiler::profiler(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* user_data)
    : callback(callback)
    , user_data(user_data)
    , running(false)
    , config(SAMPLING_CONFIG_DEFAULT) {
    if (config) this->config = *config;
    sample_buffer.reserve(this->config.max_buffer_size);
}

/**
 * Destructor that ensures sampling is stopped.
 */
profiler::~profiler() {
    if (running) stop_sampling();
}

/**
 * Samples a single thread's stack.
 *
 * @param thread The thread to sample
 */
void profiler::sample_thread(thread_t thread) {
    // ############################################
    if (thread_suspend(thread) != KERN_SUCCESS) return;
    // CRITICAL: Thread is suspended - avoid operations that could deadlock
    //
    // The suspended thread may be holding system locks (memory allocator, pthread, etc).
    // If we try to acquire these same locks while the thread is suspended, we'll deadlock.
    //
    // Specifically avoid:
    // - Memory allocations (new, malloc) - memory allocator locks
    // - System calls that acquire locks - they may be held by suspended thread
    // - pthread functions - they share locks with system APIs
    auto trace = walk_stack(thread);
    thread_resume(thread);
    // ############################################

    if (trace.frame_count > 0) {
        sample_buffer.push_back(trace);
        if (sample_buffer.size() >= config.max_buffer_size) {
            flush_buffer();
        }
    }
}

/**
 * Flushes the sample buffer by calling the callback with collected traces.
 */
void profiler::flush_buffer() {
    if (sample_buffer.empty()) return;
    callback(sample_buffer.data(), sample_buffer.size(), user_data);
    sample_buffer.clear();
}

/**
 * Main sampling loop that collects stack traces from threads.
 */
void profiler::sampling_loop() {
    while (running) {
        if (config.profile_current_thread_only) {
            sample_thread(pthread_mach_thread_np(target_thread));
            continue;
        }

        thread_act_array_t threads;
        mach_msg_type_number_t count;
        if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        for (mach_msg_type_number_t i = 0; i < count; i++) {
            if (!running) break;
            if (threads[i] == pthread_mach_thread_np(pthread_self())) continue;
            sample_thread(threads[i]);
        }

        for (mach_msg_type_number_t i = 0; i < count; i++) {
            mach_port_deallocate(mach_task_self(), threads[i]);
        }

        vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t));

        std::this_thread::sleep_for(
            std::chrono::milliseconds(config.sampling_interval_ms));
    }
    
    flush_buffer();
}

/**
 * Starts the sampling process.
 *
 * @return true if sampling was started successfully
 */
bool profiler::start_sampling() {
    if (running) return false;

    if (config.profile_current_thread_only) {
        target_thread = pthread_self();
    }

    running = true;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    struct sched_param param;
    param.sched_priority = 50;
    pthread_attr_setschedparam(&attr, &param);
    
    pthread_create(&sampling_thread, &attr, [](void* arg) -> void* {
        static_cast<profiler*>(arg)->sampling_loop();
        return nullptr;
    }, this);
    
    pthread_attr_destroy(&attr);
    return running;
}

/**
 * Stops the sampling process.
 */
void profiler::stop_sampling() {
    if (!running) return;
    running = false;
    pthread_join(sampling_thread, nullptr);
}

} // namespace profiler
} // namespace dd

extern "C" {

/**
 * Creates a new profiler instance.
 *
 * @param config The sampling configuration to use
 * @param callback Function to call with collected stack traces
 * @param user_data User data to pass to the callback
 * @return A new profiler instance or nullptr if creation failed
 */
profiler_t* profiler_create(
    const sampling_config_t* config,
    stack_trace_callback_t callback,
    void* user_data) {
    if (!callback) return nullptr;
    return new dd::profiler::profiler(config, callback, user_data);
}

/**
 * Destroys a profiler instance.
 * @param profiler The profiler instance to destroy
 */
void profiler_destroy(profiler_t* profiler) {
    if (!profiler) return;
    delete static_cast<dd::profiler::profiler*>(profiler);
}

/**
 * Starts profiling.
 *
 * @param profiler The profiler instance to start
 * @return 1 if profiling was started successfully, 0 otherwise
 */
int profiler_start(profiler_t* profiler) {
    if (!profiler) return 0;
    auto* prof = static_cast<dd::profiler::profiler*>(profiler);
    return prof->start_sampling() ? 1 : 0;
}

/**
 * Stops profiling.
 *
 * @param profiler The profiler instance to stop
 */
void profiler_stop(profiler_t* profiler) {
    if (!profiler) return;
    auto* prof = static_cast<dd::profiler::profiler*>(profiler);
    prof->stop_sampling();
}

/**
 * Checks if profiling is currently running.
 * 
 * @param profiler The profiler instance to check
 * @return 1 if profiling is running, 0 otherwise
 */
int profiler_is_running(const profiler_t* profiler) {
    if (!profiler) return 0;
    auto* prof = static_cast<const dd::profiler::profiler*>(profiler);
    return prof->running ? 1 : 0;
}

} // extern "C"

#endif // __APPLE__ 
