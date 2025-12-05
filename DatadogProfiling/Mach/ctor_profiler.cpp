/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "ctor_profiler.h"

#ifdef __APPLE__

#include "profile.h"
#include "mach_sampling_profiler.h"

#include <CoreFoundation/CoreFoundation.h>
#include <cstdlib>
#include <cstring>
#include <random>

// UserDefaults configuration
#define DD_USER_DEFAULTS_SUITE_NAME "com.datadoghq.ios-sdk"
#define DD_IS_PROFILING_ENABLED_KEY "is_profiling_enabled"

static constexpr int64_t CTOR_PROFILER_TIMEOUT_NS = 5000000000ULL; // 5 seconds

namespace dd::profiler { class ctor_profiler; }

static dd::profiler::ctor_profiler* g_ctor_profiler = nullptr;

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
    CFStringRef suiteName = CFSTR(DD_USER_DEFAULTS_SUITE_NAME);
    CFStringRef key = CFSTR(DD_IS_PROFILING_ENABLED_KEY);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, suiteName);

    bool result = false;

    if (value) {
         if (CFGetTypeID(value) == CFDataGetTypeID()) {
             CFDataRef data = (CFDataRef)value;
             CFIndex length = CFDataGetLength(data);
             const CFIndex versionLength = 2;

             // Check we have bytes for version (2 bytes) and for the data (at least 1 byte for bool)
             if (length >= versionLength + 1) {
                 const UInt8* bytes = CFDataGetBytePtr(data);
                 const UInt8* storedData = bytes + versionLength;

                 // Read bool as a single byte
                 result = (storedData[0] != 0);
             }
         }
         CFRelease(value);
     }

    return result;
}

/**
 * Deletes the DatadogProfiling defaults from the `UserDefaults`
 * to be re-evaluated during `Profiling.enable()`.
 */
void delete_profiling_defaults() {
    CFStringRef suiteName = CFSTR(DD_USER_DEFAULTS_SUITE_NAME);
    CFStringRef key = CFSTR(DD_IS_PROFILING_ENABLED_KEY);

    CFPreferencesSetValue(key, NULL, suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(suiteName, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

#ifdef __cplusplus
}
#endif

namespace dd::profiler {

/**
 * Encapsulates profiler state and operations
 */
class ctor_profiler {
public:
    ctor_profiler_status_t status = CTOR_PROFILER_STATUS_NOT_STARTED;

    ctor_profiler(
        double sample_rate = 0.0,
        bool is_prewarming = false,
        int64_t timeout_ns = CTOR_PROFILER_TIMEOUT_NS
    ) : sample_rate(sample_rate), is_prewarming(is_prewarming), timeout_ns(timeout_ns) {}

    ~ctor_profiler() {
        if (profiler) delete profiler;
        if (profile) delete profile;
    }

    /**
     * Start the profiler using constructor configuration
     */
    void start() {
        if (is_prewarming) {
            status = CTOR_PROFILER_STATUS_PREWARMED;
            return;
        }

        if (!sample(sample_rate)) {
            status = CTOR_PROFILER_STATUS_SAMPLED_OUT;
            return;
        }

        // Use 101 Hz sampling frequency
        uint64_t sampling_interval_ns = 9900990; // ~101 Hz (1/101 seconds ≈ 9.9ms)

        // Create profile aggregator
        profile = new dd::profiler::profile(sampling_interval_ns);
        if (!profile) {
            status = CTOR_PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        // Configure profiler
        sampling_config_t config = SAMPLING_CONFIG_DEFAULT;
        config.sampling_interval_nanos = sampling_interval_ns;

        profiler = new mach_sampling_profiler(&config, callback, this);
        if (!profiler) {
            delete profile;
            profile = nullptr;
            status = CTOR_PROFILER_STATUS_ALLOCATION_FAILED;
            return;
        }

        status = CTOR_PROFILER_STATUS_RUNNING;
        if (!profiler->start_sampling()) {
            delete profiler;
            delete profile;
            profiler = nullptr;
            profile = nullptr;
            status = CTOR_PROFILER_STATUS_ALREADY_STARTED;
            return;
        }
    }

    // Non-copyable
    ctor_profiler(const ctor_profiler&) = delete;
    ctor_profiler& operator=(const ctor_profiler&) = delete;


    void stop() {
        if (!profiler) return;
        status = CTOR_PROFILER_STATUS_STOPPED;
        profiler->stop_sampling();
        delete profiler;
        profiler = nullptr;
    }

    profile* get_profile() const { return profile; }

private:
    mach_sampling_profiler* profiler = nullptr;
    profile* profile = nullptr;
    double sample_rate = 0.0;
    bool is_prewarming = false;
    int64_t timeout_ns = CTOR_PROFILER_TIMEOUT_NS; // 5 seconds default

    /**
     * Static callback function to handle collected stack traces
     *
     * @param traces Array of captured stack traces
     * @param count Number of traces in the array
     * @param ctx Context pointer to ctor_profiler instance
     */
    static void callback(const stack_trace_t* traces, size_t count, void* ctx) {
        if (!traces || count == 0 || !ctx) return;

        ctor_profiler* profiler = static_cast<ctor_profiler*>(ctx);

        dd::profiler::profile* profile = profiler->profile;
        if (!profile) return;
        profile->add_samples(traces, count);

        // Check for timeout after adding samples
        int64_t duration_ns = profile->end_timestamp() - profile->start_timestamp();
        if (duration_ns > profiler->timeout_ns) {
            profiler->stop();
            profiler->status = CTOR_PROFILER_STATUS_TIMEOUT;
        }
    }
};

} // namespace dd::profiler

/**
 * Constructor function that runs early during app launch to check if
 * constructor-based profiling should be enabled based on bundle configuration
 * and prewarming.
 * 
 * Uses high priority (65535) to run as close to main() as possible.
 */
__attribute__((constructor(65535)))
static void ctor_profiler_auto_start() {
    if (!is_profiling_enabled()) {
        return;
    }

    // Reset profiling defaults to be re-evaluated again
    delete_profiling_defaults();

    // Create profiler and start with sample rate
    g_ctor_profiler = new dd::profiler::ctor_profiler(DD_PROFILING_SAMPLE_RATE, is_active_prewarm());
    g_ctor_profiler->start();
}

// C API implementations

void ctor_profiler_stop(void) {
    if (g_ctor_profiler) g_ctor_profiler->stop();
}

ctor_profiler_status_t ctor_profiler_get_status(void) {
    return g_ctor_profiler ? g_ctor_profiler->status : CTOR_PROFILER_STATUS_NOT_STARTED;
}

ctor_profile_t* ctor_profiler_get_profile(void) {
    return g_ctor_profiler ? reinterpret_cast<ctor_profile_t*>(g_ctor_profiler->get_profile()) : nullptr;
}

void ctor_profiler_destroy(void) {
    delete g_ctor_profiler;
    g_ctor_profiler = nullptr;
}

#ifdef __cplusplus
extern "C" {
#endif

void ctor_profiler_start_testing(double sample_rate, bool is_prewarming, int64_t timeout_ns) {
    delete g_ctor_profiler;
    g_ctor_profiler = new dd::profiler::ctor_profiler(sample_rate, is_prewarming, timeout_ns);
    g_ctor_profiler->start();
}

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
