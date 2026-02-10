/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "mach_profiler.h"

#ifdef __APPLE__

#include "profile.h"
#include "mach_sampling_profiler.h"

#include <CoreFoundation/CoreFoundation.h>
#include <random>
#include <mutex>
#include <pthread.h>
#include <queue>
#include <atomic>
#include <unordered_map>

static constexpr int64_t PROFILER_TIMEOUT_NS = 60000000000ULL; // 60 seconds

namespace dd::profiler { class mach_profiler; }

static dd::profiler::mach_profiler* mach_profiler = nullptr;
static std::mutex g_mach_profiler_mutex;

/**
 * Checks if ThreadSanitizer is enabled
 * and without options to avoid halts.
 *
 * @return true if ThreadSanitizer is enabled, false otherwise
 */
bool is_thread_sanitizer_enabled() {
#if __has_feature(thread_sanitizer)
    const char* tsanOptions = getenv("TSAN_OPTIONS");
    if (tsanOptions != nullptr) {
        return (strstr(tsanOptions, "halt_on_error=0") == nullptr)
        || (strstr(tsanOptions, "report_bugs=0") == nullptr);
    }
    return true;
#endif
    return false;
}

/**
 * Checks if the current process was launched via pre-warming by examining
 * the ActivePrewarm environment variable.
 *
 * @return true if the process is actively pre-warmed, false otherwise
 */
bool is_active_prewarm() {
    const char* prewarm = getenv("ActivePrewarm");
    return prewarm != nullptr && strcmp(prewarm, "1") == 0;
}

/**
 * Determines whether profiling should be enabled based on the sample rate
 * using probabilistic sampling.
 *
 * @param sample_rate The sample rate percentage (0.0 to 100.0)
 * @return true if profiling should be enabled, false otherwise
 */
bool sample(double sample_rate) {
    if (sample_rate <= 0.0) return false;
    if (sample_rate >= 100.0) return true;

    // Use probabilistic sampling based on the sample rate (0-100%)
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_real_distribution<double> dis(0.0, 100.0);

    double random_value = dis(gen);
    return random_value < sample_rate;
}

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Reads the DatadogProfiling info from the `UserDefaults`
 * to validate that the feature was enabled before.
 *
 * @return If Profiling was enabled, or false if the key is not found
 */
bool is_profiling_enabled() {
    CFStringRef suiteName = CFSTR(DD_PROFILING_USER_DEFAULTS_SUITE_NAME);
    CFStringRef key = CFSTR(DD_PROFILING_IS_ENABLED_KEY);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, suiteName);

    bool result = false;

    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
            result = CFBooleanGetValue((CFBooleanRef)value);
        }
        CFRelease(value);
    }

    return result;
}

/**
 * Reads the DatadogProfiling sample rate from the `UserDefaults`
 *
 * @return The sample rate as a double, or 0.0 if not found or invalid
 */
double read_profiling_sample_rate() {
    CFStringRef suiteName = CFSTR(DD_PROFILING_USER_DEFAULTS_SUITE_NAME);
    CFStringRef key = CFSTR(DD_PROFILING_SAMPLE_RATE_KEY);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, suiteName);
    
    double sample_rate = 0.0;
    
    if (value) {
        if (CFGetTypeID(value) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &sample_rate);
        }
        CFRelease(value);
    }
    
    // Validate sample rate is between 0 and 100
    if (sample_rate < 0.0) return 0.0;
    if (sample_rate > 100.0) return 100.0;
    
    return sample_rate;
}

/**
 * Deletes the DatadogProfiling defaults from the `UserDefaults`
 * to be re-evaluated during `Profiling.enable()`.
 */
void delete_profiling_defaults() {
    CFStringRef suiteName = CFSTR(DD_PROFILING_USER_DEFAULTS_SUITE_NAME);
    CFStringRef isEnabledKey = CFSTR(DD_PROFILING_IS_ENABLED_KEY);
    CFStringRef sampleRateKey = CFSTR(DD_PROFILING_SAMPLE_RATE_KEY);

    CFPreferencesSetValue(isEnabledKey, NULL, suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue(sampleRateKey, NULL, suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

#ifdef __cplusplus
}
#endif

namespace dd::profiler {

/**
 * Encapsulates profiler state and operations
 */
class mach_profiler {
public:
    profiler_status_t status = PROFILER_STATUS_NOT_STARTED;

    mach_profiler(
        double sample_rate = 0.0,
        bool is_prewarming = false,
        int64_t timeout_ns = PROFILER_TIMEOUT_NS
    ) : sample_rate(sample_rate), is_prewarming(is_prewarming), timeout_ns(timeout_ns) {
        pthread_mutex_init(&resolver_mutex, nullptr);
        pthread_cond_init(&resolver_cv, nullptr);
    }

    ~mach_profiler() {
        stop();
        stop_resolver();
        if (profiler) delete profiler;
        if (profile) delete profile;
        pthread_mutex_destroy(&resolver_mutex);
        pthread_cond_destroy(&resolver_cv);
    }

    /**
     * Start the profiler.
     */
    void start() {
        if (is_thread_sanitizer_enabled()) {
            printf("[DATADOG SDK] 🐶 → Profiling is disabled because ThreadSanitizer is active. Please disable ThreadSanitizer to enable profiling.\n");
            status = PROFILER_STATUS_NOT_STARTED;
            return;
        }

        if (status == PROFILER_STATUS_RUNNING) return;

        if (is_prewarming) {
            status = PROFILER_STATUS_PREWARMED;
            return;
        }

        if (!sample(sample_rate)) {
            status = PROFILER_STATUS_SAMPLED_OUT;
            return;
        }

        // Start resolver thread first
        if (!start_resolver()) {
            status = PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        // Create profile aggregator
        if (!create_profile()) {
            stop_resolver();
            return;
        }

        // Configure profiler
        sampling_config_t config = SAMPLING_CONFIG_DEFAULT;
        config.sampling_interval_nanos = SAMPLING_CONFIG_DEFAULT_INTERVAL_NS;
        config.ignore_thread = resolver_thread;

        profiler = new mach_sampling_profiler(&config, callback, this);
        if (!profiler) {
            delete profile;
            profile = nullptr;
            stop_resolver();
            status = PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        status = PROFILER_STATUS_RUNNING;
        if (!profiler->start_sampling()) {
            delete profiler;
            delete profile;
            profiler = nullptr;
            profile = nullptr;
            stop_resolver();
            status = PROFILER_STATUS_ALREADY_STARTED;
            return;
        }
    }

    // Non-copyable
    mach_profiler(const mach_profiler&) = delete;
    mach_profiler& operator=(const mach_profiler&) = delete;


    void stop() {
        if (!profiler) return;
        status = PROFILER_STATUS_STOPPED;
        profiler->stop_sampling();
    }

    /**
     * Retrieves the profile data.
     * 
     * @param cleanup If true, takes ownership of the profile data, removing it from the profiler.
     *                Subsequent calls will return nullptr.
     * @return The profile data, or nullptr if none exists
     */
    profile* get_profile(bool cleanup = false) {
        if (profiler) {
            profiler->flush_buffer(true); // Blocking flush from get_profile
        }

        // Always wait for resolver to catch up to ensure all captured samples are processed
        flush_resolver();

        // Lock to safely handle the profile pointer swap
        pthread_mutex_lock(&resolver_mutex);
        dd::profiler::profile* p = profile;
        if (cleanup) {
            profile = nullptr;
            create_profile_internal(); // Private method without locking
        }
        pthread_mutex_unlock(&resolver_mutex);
        
        return p;
    }

private:
    mach_sampling_profiler* profiler = nullptr;
    profile* profile = nullptr;
    double sample_rate = 0.0;
    bool is_prewarming = false;
    int64_t timeout_ns = PROFILER_TIMEOUT_NS;

    // Background resolver for symbolication
    pthread_t resolver_thread;
    pthread_mutex_t resolver_mutex;
    pthread_cond_t resolver_cv;
    std::queue<std::vector<stack_trace_t>> resolver_queue;
    std::atomic<bool> resolver_running{false};
    std::atomic<bool> processing_batch{false};
    std::unordered_map<uint64_t, binary_image_t> batch_cache;

    bool start_resolver() {
        if (resolver_running) return true;
        resolver_running = true;
        
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        // Use higher priority for resolver to avoid priority inversion when holding dyld lock
        pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INITIATED, 0);
        
        if (pthread_create(&resolver_thread, &attr, resolver_thread_entry, this) != 0) {
            resolver_running = false;
            pthread_attr_destroy(&attr);
            return false;
        }
        pthread_attr_destroy(&attr);
        return true;
    }

    void stop_resolver() {
        if (!resolver_running) return;
        resolver_running = false;
        
        pthread_mutex_lock(&resolver_mutex);
        pthread_cond_signal(&resolver_cv);
        pthread_mutex_unlock(&resolver_mutex);
        
        pthread_join(resolver_thread, nullptr);
    }

    void flush_resolver() {
        pthread_mutex_lock(&resolver_mutex);
        while (!resolver_queue.empty() || processing_batch) {
            pthread_cond_wait(&resolver_cv, &resolver_mutex);
        }
        pthread_mutex_unlock(&resolver_mutex);
    }

    static void* resolver_thread_entry(void* arg) {
        pthread_setname_np("com.datadoghq.profiler.resolver");
        static_cast<mach_profiler*>(arg)->resolver_loop();
        return nullptr;
    }

    void resolver_loop() {
        while (resolver_running || !resolver_queue.empty()) {
            std::vector<stack_trace_t> batch;
            
            pthread_mutex_lock(&resolver_mutex);
            while (resolver_queue.empty() && resolver_running) {
                pthread_cond_wait(&resolver_cv, &resolver_mutex);
            }
            
            if (!resolver_queue.empty()) {
                batch = std::move(resolver_queue.front());
                resolver_queue.pop();
                processing_batch = true; // Signal we are busy
            }
            pthread_mutex_unlock(&resolver_mutex);

            if (batch.empty()) continue;

            // Reuse map to avoid re-allocations
            batch_cache.clear();

            // Resolve and add to profile
            for (auto& trace : batch) {
                for (uint32_t j = 0; j < trace.frame_count; j++) {
                    auto& frame = trace.frames[j];
                    
                    auto cached = batch_cache.find(frame.instruction_ptr);
                    if (cached != batch_cache.end()) {
                        binary_image_init(&frame.image);
                        frame.image.load_address = cached->second.load_address;
                        memcpy(frame.image.uuid, cached->second.uuid, sizeof(uuid_t));
                        if (cached->second.filename) {
                            frame.image.filename = strdup(cached->second.filename);
                        }
                    } else {
                        binary_image_init(&frame.image);
                        if (binary_image_lookup_pc(&frame.image, (void*)frame.instruction_ptr)) {
                            // Cache the result for this batch
                            binary_image_t entry;
                            entry.load_address = frame.image.load_address;
                            memcpy(entry.uuid, frame.image.uuid, sizeof(uuid_t));
                            entry.filename = frame.image.filename ? strdup(frame.image.filename) : nullptr;
                            batch_cache[frame.instruction_ptr] = entry;
                        }
                    }
                }
            }

            pthread_mutex_lock(&resolver_mutex);
            if (profile) {
                profile->add_samples(batch.data(), batch.size());
            }
            pthread_mutex_unlock(&resolver_mutex);

            // Clean up traces
            for (auto& trace : batch) {
                stack_trace_destroy(&trace);
            }

            // Clean up filenames in persistent batch cache
            for (auto& pair : batch_cache) {
                if (pair.second.filename) free((void*)pair.second.filename);
            }

            // Signal we are done with this batch and notify waiting threads
            pthread_mutex_lock(&resolver_mutex);
            processing_batch = false;
            pthread_cond_broadcast(&resolver_cv);
            pthread_mutex_unlock(&resolver_mutex);
        }
    }

    /**
     * Internal helper to create a fresh profile aggregator.
     * 
     * @return true if successful, false on allocation failure
     */
    bool create_profile() {
        pthread_mutex_lock(&resolver_mutex);
        bool result = create_profile_internal();
        pthread_mutex_unlock(&resolver_mutex);
        return result;
    }

private:
    bool create_profile_internal() {
        // Create profile aggregator
        profile = new dd::profiler::profile(SAMPLING_CONFIG_DEFAULT_INTERVAL_NS);
        if (!profile) {
            status = PROFILER_STATUS_ALLOCATION_FAILED;
            return false;
        }
        return true;
    }

    /**
     * Static callback function to handle collected stack traces.
     * Called from the high-priority sampling thread.
     *
     * @param traces Vector of captured stack traces.
     * @param ctx Context pointer to mach_profiler instance.
     */
    static void callback(std::vector<stack_trace_t>& traces, bool blocking, void* ctx) {
        if (traces.empty() || !ctx) return;

        mach_profiler* profiler = static_cast<mach_profiler*>(ctx);

        if (!blocking) {
            // Use trylock to avoid deadlock if sampling thread suspends a thread holding the lock
            if (pthread_mutex_trylock(&profiler->resolver_mutex) == 0) {
                profiler->resolver_queue.push(std::move(traces));
                pthread_cond_signal(&profiler->resolver_cv);
                pthread_mutex_unlock(&profiler->resolver_mutex);
            } else {
                // Drop samples if lock is contested to ensure sampling thread never blocks
                for (auto& trace : traces) {
                    stack_trace_destroy(&trace);
                }
            }
        } else {
            // If blocking is requested (e.g. from get_profile), we MUST wait
            // to ensure no data is lost during the flush.
            pthread_mutex_lock(&profiler->resolver_mutex);
            profiler->resolver_queue.push(std::move(traces));
            pthread_cond_signal(&profiler->resolver_cv);
            pthread_mutex_unlock(&profiler->resolver_mutex);
        }

        // Check for timeout
        if (profiler->profile) {
            int64_t duration_ns = profiler->profile->end_timestamp() - profiler->profile->start_timestamp();
            if (duration_ns > profiler->timeout_ns) {
                profiler->stop();
                profiler->status = PROFILER_STATUS_TIMEOUT;
            }
        }
    }
};

} // namespace dd::profiler

/**
 * Wrapper for pthread_create to call profiler_cache_binary_images
 */
static void* cache_binary_images_thread_entry(void*) {
    pthread_setname_np("com.datadoghq.profiler.cache-images");
    profiler_cache_binary_images();
    return nullptr;
}

/**
 * Pre-cache binary images in a background thread
 */
static void start_binary_image_caching() {
    pthread_t cache_thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_UTILITY, 0);
    if (pthread_create(&cache_thread, &attr, cache_binary_images_thread_entry, nullptr) == 0) {
        pthread_detach(cache_thread);
    }
    pthread_attr_destroy(&attr);
}

/**
 * Constructor function that runs early during app launch to check if
 * constructor-based profiling should be enabled based on bundle configuration
 * and prewarming.
 * 
 * Uses high priority (65535) to run as close to main() as possible.
 */
__attribute__((constructor(65535)))
static void mach_profiler_auto_start() {
    if (!is_profiling_enabled()) {
        return;
    }

    set_main_thread(pthread_self());

    // Pre-cache binary images in a background thread
    start_binary_image_caching();

    // Create profiler and start with sample rate
    mach_profiler = new dd::profiler::mach_profiler(read_profiling_sample_rate(), is_active_prewarm());
    mach_profiler->start();

    // Reset profiling defaults to be re-evaluated again
    delete_profiling_defaults();
}

// C API implementations

extern "C" {

void profiler_start(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    if (mach_profiler && mach_profiler->status != PROFILER_STATUS_RUNNING) mach_profiler->start();
}

void profiler_stop(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    if (mach_profiler) mach_profiler->stop();
}

profiler_status_t profiler_get_status(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    return mach_profiler ? mach_profiler->status : PROFILER_STATUS_NOT_CREATED;
}

profiler_profile_t* profiler_get_profile(bool cleanup) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    return mach_profiler ? reinterpret_cast<profiler_profile_t*>(mach_profiler->get_profile(cleanup)) : nullptr;
}

void profiler_destroy(void) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    delete mach_profiler;
    mach_profiler = nullptr;
}

void profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns) {
    std::lock_guard<std::mutex> lock(g_mach_profiler_mutex);
    delete mach_profiler;
    mach_profiler = new dd::profiler::mach_profiler(sample_rate, is_prewarming);
    mach_profiler->start();
}

} // extern "C"

#endif // __APPLE__
