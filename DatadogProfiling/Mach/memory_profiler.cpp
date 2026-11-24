/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH && !TARGET_OS_OSX

#include "memory_profiler_testing.h"
#include "objc_alloc_hook.h"
#include "poisson_allocation_sampler.h"
#include "swift_alloc_hook.h"

#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <execinfo.h>
#include <limits>
#include <mutex>
#include <new>
#include <time.h>

#if defined(DEBUG)
#include <objc/message.h>
#include <objc/runtime.h>
#endif

namespace {

bool start_at_launch();

void auto_start(CFStringRef suite_name, bool prewarming, bool thread_sanitizer) {
    const CFStringRef key = CFSTR(DD_PROFILING_MEMORY_SAMPLE_RATE_KEY);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, suite_name);
    double sample_rate = 0;
    if (value != nullptr) {
        if (CFGetTypeID(value) == CFNumberGetTypeID() &&
            !CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberDoubleType, &sample_rate)) {
            sample_rate = 0;
        }
        CFRelease(value);
    }

    // The memory rate carries its own previous-run enablement. Consuming only
    // this key keeps startup independent of the CPU constructor's ordering.
    CFPreferencesSetValue(key, nullptr, suite_name, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(suite_name, kCFPreferencesCurrentUser,
                            kCFPreferencesAnyHost);
    if (prewarming || thread_sanitizer || !std::isfinite(sample_rate) || sample_rate <= 0) {
        return;
    }
    // Sampling controls emission in Swift. Recording must span sampled-out
    // sessions so later live-set snapshots retain their surviving objects.
    start_at_launch();
}

class dd_memory_profiler;
dd_memory_profiler *g_observer_owner = nullptr;

void observe_swift_allocation(const void *, uint64_t, const HeapMetadata *,
                              dd_swift_class_name_resolver_t);
void observe_objc_allocation(const void *, uint64_t, const char *);
void observe_deallocation(const void *);

#if defined(DEBUG)
void ignore_swift_allocation(const void *, uint64_t, const HeapMetadata *,
                             dd_swift_class_name_resolver_t) {}
void ignore_objc_allocation(const void *, uint64_t, const char *) {}
void ignore_deallocation(const void *) {}
#endif

bool clock_origin(int64_t &monotonic, int64_t &realtime) {
    timespec wall{};
    if (clock_gettime(CLOCK_REALTIME, &wall) != 0) {
        return false;
    }
    monotonic = static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
    realtime = (static_cast<int64_t>(wall.tv_sec) * 1000000000LL) + wall.tv_nsec;
    return monotonic > 0 && realtime > 0;
}

class observation_scope {
public:
    explicit observation_scope(bool &is_observing) : observing(is_observing), entered(!is_observing) {
        if (entered) {
            observing = true;
        }
    }
    ~observation_scope() {
        if (entered) {
            observing = false;
        }
    }
    observation_scope(const observation_scope &) = delete;
    observation_scope &operator=(const observation_scope &) = delete;
    observation_scope(observation_scope &&) = delete;
    observation_scope &operator=(observation_scope &&) = delete;
    bool has_entered() const { return entered; }

private:
    bool &observing;
    bool entered;
};

class dd_memory_profiler {
public:
    dd_memory_profiler() = default;
    ~dd_memory_profiler() = default;
    dd_memory_profiler(const dd_memory_profiler &) = delete;
    dd_memory_profiler &operator=(const dd_memory_profiler &) = delete;
    dd_memory_profiler(dd_memory_profiler &&) = delete;
    dd_memory_profiler &operator=(dd_memory_profiler &&) = delete;

    bool start(bool testing = false, uint32_t failed_hook = 0, bool at_launch = false);
    void pause();
    void resume();
    void stop();
    bool is_running() const { return running.load(std::memory_order_acquire); }
    bool was_started_at_launch() {
        std::lock_guard<std::mutex> lock(lifecycle_mutex);
        return started_at_launch;
    }
    bool is_paused() const {
        return is_running() && (allocation_epoch.load(std::memory_order_acquire) & 1U) == 0;
    }
    int64_t window_start_time() {
        std::lock_guard<std::mutex> lock(lifecycle_mutex);
        return is_running() ? window_start_wall : 0;
    }
    int64_t window_age() {
        std::lock_guard<std::mutex> lock(lifecycle_mutex);
        if (!is_running() || window_start_monotonic <= 0) {
            return 0;
        }
        const int64_t now = static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
        return now >= window_start_monotonic ? now - window_start_monotonic : 0;
    }
    dd_memory_capture_status_t capture(dd_memory_capture_t *capture);
    dd_memory_pprof_view_t serialize(const dd_memory_capture_t *capture);
    dd_memory_profiler_diagnostics_t consume_diagnostics();
    void allocation(const void *address, uint64_t size, const char *class_name,
                    const HeapMetadata *metadata, dd_swift_class_name_resolver_t resolver);
    void deallocation(const void *address);
#if defined(DEBUG)
    void configure_for_testing(uint32_t failed_hook);
    void reset_for_testing();
    void fail_next_capture_for_testing();
    dd_memory_profiler_test_capture_diagnostics_t capture_diagnostics_for_testing();
    void test_record(const dd_memory_live_sample_t *sample);
    void test_remove(const void *address);
#endif

private:
    bool begin_selected(uint64_t epoch);
    void end_selected();
    void disable_allocations();
    void stop_locked();
    void collect_allocation_diagnostics();
    void notify_drain();
    dd_memory_capture_status_t capture_locked(dd_memory_capture_t *capture);
#if defined(DEBUG)
    void record_capture_for_testing(
        dd_memory_capture_status_t status, const dd_memory_capture_t *capture);
    bool begin_test_observation();
    void end_test_observation();
    void drain_test_observations();
#endif

    std::mutex lifecycle_mutex;
    std::mutex drain_mutex;
    std::condition_variable drained;
    std::atomic<bool> running{false};
    dd_memory_profiler_diagnostics_t diagnostics{};
    dd_memory_live_set_diagnostics_t previous_live_diagnostics{};
    uint64_t previous_swift_reentrant_skips = 0;
    uint64_t previous_objc_reentrant_skips = 0;
    std::atomic<uint64_t> sampled_allocations{0};
    std::atomic<uint64_t> reentrant_skips{0};
    bool started_at_launch = false;
    bool allocation_failed = false;
    // Odd means allocating. Every transition has a distinct epoch, so a
    // pre-pause sampler callback cannot be admitted after resume.
    std::atomic<uint64_t> allocation_epoch{0};
    std::atomic<uint64_t> selected_in_flight{0};
    std::atomic<uint64_t> sampler_session{0};
    dd_memory_allocation_window_t *window = nullptr;
    dd_memory_pprof_encoder_t *encoder = nullptr;
    uint64_t generation = 0;
    uint64_t previous_occupancy = 0;
    int64_t window_start_monotonic = 0;
    int64_t window_start_wall = 0;
    int64_t paused_end = 0;
    inline static thread_local bool observing = false;
#if defined(DEBUG)
    static constexpr uint64_t TEST_ENABLED_MASK = uint64_t{1} << 63U;
    std::atomic<uint64_t> test_observations{0};
    bool configured_testing = false;
    uint32_t configured_failed_hook = DD_MEMORY_TEST_HOOKS_SUCCEED;
    bool fail_next_capture = false;
    dd_memory_profiler_test_capture_diagnostics_t capture_diagnostics{};
#endif
};

// Initialized only through lifecycle entry points, before installing callbacks.
// Intentionally process-lived: runtime trampolines can outlive SDK teardown.
dd_memory_profiler *profiler() {
    static dd_memory_profiler *const instance = new (std::nothrow) dd_memory_profiler();
    return instance;
}

bool start_at_launch() {
    auto *owner = profiler();
    return owner != nullptr && owner->start(false, 0, true);
}

bool dd_memory_profiler::start(bool testing, uint32_t failed_hook, bool at_launch) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (allocation_failed) {
        return false;
    }
    if (is_running()) {
        return true;
    }
#if defined(DEBUG)
    if (configured_testing) {
        testing = true;
        failed_hook = configured_failed_hook;
    }
#endif
    diagnostics = {};
    diagnostics.swift_install_result = -1;
    diagnostics.objc_install_result = -1;
    previous_live_diagnostics = {};
    previous_swift_reentrant_skips = dd_swift_alloc_hook_diagnostics().reentrant_skips;
    previous_objc_reentrant_skips = dd_objc_alloc_hook_diagnostics().reentrant_skips;
    sampled_allocations.store(0, std::memory_order_relaxed);
    reentrant_skips.store(0, std::memory_order_relaxed);
    if (sampler_session.load(std::memory_order_relaxed) == std::numeric_limits<uint64_t>::max() ||
        !clock_origin(window_start_monotonic, window_start_wall)) {
        return false;
    }
    window = dd_memory_allocation_window_create();
    if (window == nullptr) {
        allocation_failed = true;
        return false;
    }
    diagnostics.recorder_storage_bytes = dd_memory_allocation_window_diagnostics(window).storage_bytes;
    generation = dd_memory_allocation_window_start(window);
    if (generation == 0) {
        dd_memory_allocation_window_destroy(window);
        window = nullptr;
        return false;
    }
    sampler_session.fetch_add(1, std::memory_order_relaxed);
    previous_occupancy = 0;
    paused_end = 0;
    g_observer_owner = this;
    auto swift_allocation = observe_swift_allocation;
    auto objc_allocation = observe_objc_allocation;
    auto deallocation = observe_deallocation;
#if defined(DEBUG)
    if (testing) {
        swift_allocation = ignore_swift_allocation;
        objc_allocation = ignore_objc_allocation;
        deallocation = ignore_deallocation;
    }
#else
    (void)testing;
    (void)failed_hook;
#endif
    const auto swift_status = dd_swift_alloc_hook_start(swift_allocation, deallocation);
    diagnostics.swift_install_result = static_cast<int32_t>(swift_status);
    bool swift_ready = swift_status == DD_SWIFT_ALLOC_HOOK_OK ||
                       swift_status == DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED;
#if defined(DEBUG)
    if (failed_hook == DD_MEMORY_TEST_SWIFT_HOOK_FAILS) {
        diagnostics.swift_install_result = DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
        swift_ready = false;
    }
#endif
    bool objc_ready = false;
    if (swift_ready) {
        const auto objc_status = dd_objc_alloc_hook_start(objc_allocation, deallocation);
        diagnostics.objc_install_result = static_cast<int32_t>(objc_status);
        objc_ready = objc_status == DD_OBJC_ALLOC_HOOK_OK ||
                     objc_status == DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED;
#if defined(DEBUG)
        if (failed_hook == DD_MEMORY_TEST_OBJC_HOOK_FAILS) {
            diagnostics.objc_install_result = DD_OBJC_ALLOC_HOOK_FAILED_INSTALL;
            objc_ready = false;
        }
#endif
    }
    if (!swift_ready || !objc_ready) {
        stop_locked();
        return false;
    }
#if defined(DEBUG)
    if (testing) {
        test_observations.store(TEST_ENABLED_MASK, std::memory_order_release);
    }
#endif
    started_at_launch = at_launch;
    running.store(true, std::memory_order_release);
    allocation_epoch.fetch_add(1);
    return true;
}

void dd_memory_profiler::notify_drain() {
    std::lock_guard<std::mutex> lock(drain_mutex);
    drained.notify_all();
}

bool dd_memory_profiler::begin_selected(uint64_t epoch) {
    selected_in_flight.fetch_add(1);
    if (allocation_epoch.load() == epoch && (epoch & 1U) != 0) {
        return true;
    }
    end_selected();
    return false;
}

void dd_memory_profiler::end_selected() {
    if (selected_in_flight.fetch_sub(1) == 1 &&
        (allocation_epoch.load() & 1U) == 0) {
        notify_drain();
    }
}

void dd_memory_profiler::disable_allocations() {
    if ((allocation_epoch.load() & 1U) != 0) {
        allocation_epoch.fetch_add(1);
    }
    std::unique_lock<std::mutex> lock(drain_mutex);
    drained.wait(lock, [this] { return selected_in_flight.load() == 0; });
}

void dd_memory_profiler::pause() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (!is_running() || is_paused()) {
        return;
    }
    disable_allocations();
    paused_end = static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
}

void dd_memory_profiler::resume() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (!is_paused()) {
        return;
    }
    int64_t monotonic = 0;
    int64_t wall = 0;
    if (!clock_origin(monotonic, wall)) {
        return;
    }
    window_start_monotonic = monotonic;
    window_start_wall = wall;
    paused_end = 0;
    allocation_epoch.fetch_add(1);
}

dd_memory_profiler_diagnostics_t dd_memory_profiler::consume_diagnostics() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    auto result = diagnostics;
    diagnostics.sampled_allocations = 0;
    diagnostics.reentrant_skips = 0;
    // The table keeps lifetime diagnostics. Consume only their reporting deltas;
    // resetting the live table here would lose surviving sampled allocations.
    auto &live = result.window.live_set;
    live.dropped_samples -= previous_live_diagnostics.dropped_samples;
    live.probe_count -= previous_live_diagnostics.probe_count;
    live.total_probe_length -= previous_live_diagnostics.total_probe_length;
    previous_live_diagnostics = diagnostics.window.live_set;
    diagnostics.window = {};
    diagnostics.window.live_set = previous_live_diagnostics;
    return result;
}

void dd_memory_profiler::collect_allocation_diagnostics() {
    diagnostics.sampled_allocations += sampled_allocations.exchange(0, std::memory_order_relaxed);
    const auto swift_skips = dd_swift_alloc_hook_diagnostics().reentrant_skips;
    const auto objc_skips = dd_objc_alloc_hook_diagnostics().reentrant_skips;
    diagnostics.reentrant_skips += reentrant_skips.exchange(0, std::memory_order_relaxed) +
        (swift_skips >= previous_swift_reentrant_skips ? swift_skips - previous_swift_reentrant_skips : swift_skips) +
        (objc_skips >= previous_objc_reentrant_skips ? objc_skips - previous_objc_reentrant_skips : objc_skips);
    previous_swift_reentrant_skips = swift_skips;
    previous_objc_reentrant_skips = objc_skips;
}

void dd_memory_profiler::stop_locked() {
    started_at_launch = false;
    if (encoder != nullptr) {
        diagnostics.encoder_storage_bytes = dd_memory_pprof_encoder_diagnostics(encoder).storage_bytes;
    }
    dd_memory_pprof_encoder_destroy(encoder);
    encoder = nullptr;
    if (window == nullptr) {
        return;
    }
    disable_allocations();
    // Each hook drains its entire observer callback, including lock-free free
    // misses. The recorder can be destroyed only after both drains finish.
    dd_swift_alloc_hook_stop();
    dd_objc_alloc_hook_stop();
#if defined(DEBUG)
    drain_test_observations();
#endif
    running.store(false, std::memory_order_release);
    collect_allocation_diagnostics();
    const auto final_window = dd_memory_allocation_window_diagnostics(window);
    diagnostics.window.recorded_allocations += final_window.recorded_allocations;
    diagnostics.window.dropped_alloc_records += final_window.dropped_alloc_records;
    diagnostics.window.peak_recorded_allocations = std::max(
        diagnostics.window.peak_recorded_allocations, final_window.peak_recorded_allocations);
    diagnostics.window.live_set = final_window.live_set;
    dd_memory_allocation_window_stop(window);
    dd_memory_allocation_window_destroy(window);
    window = nullptr;
    generation = 0;
    window_start_wall = 0;
    window_start_monotonic = 0;
    paused_end = 0;
}

void dd_memory_profiler::stop() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    stop_locked();
}

dd_memory_capture_status_t dd_memory_profiler::capture(dd_memory_capture_t *capture) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    const auto status = capture_locked(capture);
#if defined(DEBUG)
    record_capture_for_testing(status, capture);
#endif
    return status;
}

dd_memory_pprof_view_t dd_memory_profiler::serialize(const dd_memory_capture_t *capture) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (!is_running() || capture == nullptr) {
        return {};
    }
    if (encoder == nullptr) {
        encoder = dd_memory_pprof_encoder_create(DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES);
    }
    diagnostics.encoder_storage_bytes = dd_memory_pprof_encoder_diagnostics(encoder).storage_bytes;
    if (!dd_memory_pprof_encoder_encode(encoder, &capture->aggregation,
                                        capture->time_nanos, capture->duration_nanos)) {
        return {};
    }
    return dd_memory_pprof_encoder_view(encoder);
}

dd_memory_capture_status_t dd_memory_profiler::capture_locked(dd_memory_capture_t *capture) {
    if (capture == nullptr) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    *capture = {};
#if defined(DEBUG)
    if (fail_next_capture) {
        fail_next_capture = false;
        return DD_MEMORY_CAPTURE_FAILED;
    }
#endif
    if (!is_running()) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    const int64_t end = is_paused() ? paused_end :
        static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
    if (end < window_start_monotonic) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    // Freeze observer counts before closing the window. Aggregation, name
    // resolution and serialization may allocate into the following window.
    collect_allocation_diagnostics();
    if (!dd_memory_allocation_window_close(window, generation)) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    diagnostics.window = dd_memory_allocation_window_closed_diagnostics(window);
    const auto &closed = diagnostics.window;
    capture->aggregation = dd_memory_allocation_window_view(window);
    capture->time_nanos = window_start_wall;
    capture->duration_nanos = end - window_start_monotonic;
    window_start_wall += capture->duration_nanos;
    window_start_monotonic = end;
    const bool idle = closed.recorded_allocations == 0 &&
                      closed.dropped_alloc_records == 0 &&
                      closed.live_set.occupancy == previous_occupancy;
    previous_occupancy = closed.live_set.occupancy;
    return idle ? DD_MEMORY_CAPTURE_IDLE : DD_MEMORY_CAPTURE_READY;
}

void dd_memory_profiler::allocation(
    const void *address, uint64_t size, const char *class_name,
    const HeapMetadata *metadata, dd_swift_class_name_resolver_t resolver) {
    const uint64_t epoch = allocation_epoch.load(std::memory_order_acquire);
    if ((epoch & 1U) == 0) {
        return;
    }
    observation_scope scope(observing);
    if (!scope.has_entered()) {
        reentrant_skips.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    thread_local dd::profiler::poisson_allocation_sampler sampler;
    const auto selected = sampler.sample(size, sampler_session.load(std::memory_order_relaxed));
    if (selected.object_weight != 0) {
        sampled_allocations.fetch_add(1, std::memory_order_relaxed);
    }
    if (selected.object_weight == 0 || !begin_selected(epoch)) {
        return;
    }
    dd_memory_live_sample_t sample{};
    sample.address = address;
    sample.size = size;
    sample.weight = selected.object_weight;
    sample.class_name = class_name;
    sample.swift_metadata = metadata;
    sample.swift_name_resolver = resolver;
    sample.source = metadata == nullptr ? DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC :
                                         DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT;
    std::array<void *, DD_MEMORY_LIVE_SET_MAX_FRAMES> frames{};
    const int count = backtrace(frames.data(), static_cast<int>(frames.size()));
    // Omit the coordinator and observer frames, retaining the runtime caller.
    constexpr int skip = 2;
    for (int index = skip; index < count; ++index) {
        sample.frames[sample.frame_count++] = reinterpret_cast<uintptr_t>(frames[index]);
    }
    dd_memory_allocation_window_record(window, generation, &sample);
    end_selected();
}

void dd_memory_profiler::deallocation(const void *address) {
    observation_scope scope(observing);
    if (scope.has_entered()) {
        dd_memory_allocation_window_remove(window, generation, address);
    }
}

#if defined(DEBUG)
void dd_memory_profiler::configure_for_testing(uint32_t failed_hook) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    stop_locked();
    configured_testing = true;
    configured_failed_hook = failed_hook;
    fail_next_capture = false;
    capture_diagnostics = {};
}

void dd_memory_profiler::reset_for_testing() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    stop_locked();
    configured_testing = false;
    configured_failed_hook = DD_MEMORY_TEST_HOOKS_SUCCEED;
    allocation_failed = false;
    fail_next_capture = false;
    capture_diagnostics = {};
}

void dd_memory_profiler::fail_next_capture_for_testing() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    fail_next_capture = true;
}

dd_memory_profiler_test_capture_diagnostics_t dd_memory_profiler::capture_diagnostics_for_testing() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    return capture_diagnostics;
}

void dd_memory_profiler::record_capture_for_testing(
    dd_memory_capture_status_t status, const dd_memory_capture_t *capture) {
    const uint64_t captures_count = capture_diagnostics.captures_count + 1;
    const uint64_t ready_count = capture_diagnostics.ready_count +
        (status == DD_MEMORY_CAPTURE_READY ? 1 : 0);
    const uint64_t idle_count = capture_diagnostics.idle_count +
        (status == DD_MEMORY_CAPTURE_IDLE ? 1 : 0);
    capture_diagnostics = {};
    capture_diagnostics.captures_count = captures_count;
    capture_diagnostics.ready_count = ready_count;
    capture_diagnostics.idle_count = idle_count;
    capture_diagnostics.last_status = status;
    if (status == DD_MEMORY_CAPTURE_FAILED || capture == nullptr) {
        return;
    }
    capture_diagnostics.time_nanos = capture->time_nanos;
    capture_diagnostics.duration_nanos = capture->duration_nanos;
    capture_diagnostics.sample_count = capture->aggregation.count;
    for (size_t index = 0; index < capture->aggregation.count; ++index) {
        const auto &sample = capture->aggregation.samples[index];
        capture_diagnostics.alloc_objects += sample.alloc_objects;
        capture_diagnostics.alloc_space += sample.alloc_space;
        capture_diagnostics.inuse_objects += sample.inuse_objects;
        capture_diagnostics.inuse_space += sample.inuse_space;
    }
}

bool dd_memory_profiler::begin_test_observation() {
    uint64_t state = test_observations.load(std::memory_order_acquire);
    while ((state & TEST_ENABLED_MASK) != 0) {
        if (test_observations.compare_exchange_weak(state, state + 1,
                                                    std::memory_order_acq_rel)) {
            return true;
        }
    }
    return false;
}

void dd_memory_profiler::end_test_observation() {
    const uint64_t prior = test_observations.fetch_sub(1, std::memory_order_acq_rel);
    if ((prior & ~TEST_ENABLED_MASK) == 1 && (prior & TEST_ENABLED_MASK) == 0) {
        notify_drain();
    }
}

void dd_memory_profiler::drain_test_observations() {
    test_observations.fetch_and(~TEST_ENABLED_MASK, std::memory_order_acq_rel);
    std::unique_lock<std::mutex> lock(drain_mutex);
    drained.wait(lock, [this] { return test_observations.load(std::memory_order_acquire) == 0; });
}

void dd_memory_profiler::test_record(const dd_memory_live_sample_t *sample) {
    if (!begin_test_observation()) {
        return;
    }
    const uint64_t epoch = allocation_epoch.load(std::memory_order_acquire);
    observation_scope scope(observing);
    if (scope.has_entered() && begin_selected(epoch)) {
        sampled_allocations.fetch_add(1, std::memory_order_relaxed);
        dd_memory_allocation_window_record(window, generation, sample);
        end_selected();
    }
    end_test_observation();
}

void dd_memory_profiler::test_remove(const void *address) {
    if (!begin_test_observation()) {
        return;
    }
    deallocation(address);
    end_test_observation();
}
#endif

void observe_swift_allocation(
    const void *address, uint64_t size, const HeapMetadata *metadata,
    dd_swift_class_name_resolver_t resolver) {
    g_observer_owner->allocation(address, size, nullptr, metadata, resolver);
}

void observe_objc_allocation(const void *address, uint64_t size, const char *class_name) {
    g_observer_owner->allocation(address, size, class_name, nullptr, nullptr);
}

void observe_deallocation(const void *address) {
    g_observer_owner->deallocation(address);
}

__attribute__((constructor(65535)))
void memory_profiler_auto_start() {
    const char *prewarm = std::getenv("ActivePrewarm");
    const bool prewarming = prewarm != nullptr && std::strcmp(prewarm, "1") == 0;
#if __has_feature(thread_sanitizer)
    constexpr bool thread_sanitizer = true;
#else
    constexpr bool thread_sanitizer = false;
#endif
    auto_start(CFSTR("com.datadoghq.ios-sdk.profiling"), prewarming, thread_sanitizer);
}

} // namespace

extern "C" dd_memory_profiler_diagnostics_t dd_memory_profiler_consume_diagnostics(void) {
    auto *owner = profiler();
    return owner == nullptr ? dd_memory_profiler_diagnostics_t{} : owner->consume_diagnostics();
}

extern "C" bool dd_memory_profiler_start(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->start();
}

extern "C" bool dd_memory_profiler_was_started_at_launch(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->was_started_at_launch();
}

extern "C" bool dd_memory_profiler_is_running(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->is_running();
}

extern "C" bool dd_memory_profiler_is_paused(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->is_paused();
}

extern "C" int64_t dd_memory_profiler_window_start_time_nanos(void) {
    auto *owner = profiler();
    return owner == nullptr ? 0 : owner->window_start_time();
}

extern "C" int64_t dd_memory_profiler_window_age_nanos(void) {
    auto *owner = profiler();
    return owner == nullptr ? 0 : owner->window_age();
}

extern "C" void dd_memory_profiler_pause(void) {
    if (auto *owner = profiler()) {
        owner->pause();
    }
}

extern "C" void dd_memory_profiler_resume(void) {
    if (auto *owner = profiler()) {
        owner->resume();
    }
}

extern "C" void dd_memory_profiler_stop(void) {
    if (auto *owner = profiler()) {
        owner->stop();
    }
}

extern "C" dd_memory_capture_status_t dd_memory_profiler_capture(dd_memory_capture_t *capture) {
    auto *owner = profiler();
    if (owner == nullptr) {
        if (capture != nullptr) {
            *capture = {};
        }
        return DD_MEMORY_CAPTURE_FAILED;
    }
    return owner->capture(capture);
}

extern "C" dd_memory_pprof_view_t dd_memory_profiler_serialize(const dd_memory_capture_t *capture) {
    auto *owner = profiler();
    return owner == nullptr ? dd_memory_pprof_view_t{} : owner->serialize(capture);
}

#if defined(DEBUG)
extern "C" void dd_memory_profiler_auto_start_for_testing(
    const char *suite_name, bool prewarming, bool thread_sanitizer) {
    if (suite_name == nullptr) {
        return;
    }
    CFStringRef suite = CFStringCreateWithCString(kCFAllocatorDefault, suite_name,
                                                 kCFStringEncodingUTF8);
    if (suite != nullptr) {
        auto_start(suite, prewarming, thread_sanitizer);
        CFRelease(suite);
    }
}

extern "C" void dd_memory_profiler_configure_for_testing(dd_memory_test_hook_failure_t failure) {
    if (auto *owner = profiler()) {
        owner->configure_for_testing(failure);
    }
}

extern "C" void dd_memory_profiler_reset_for_testing(void) {
    if (auto *owner = profiler()) {
        owner->reset_for_testing();
    }
}

extern "C" dd_memory_profiler_test_capture_diagnostics_t dd_memory_profiler_capture_diagnostics_for_testing(void) {
    auto *owner = profiler();
    return owner == nullptr ? dd_memory_profiler_test_capture_diagnostics_t{} :
                             owner->capture_diagnostics_for_testing();
}

extern "C" void dd_memory_profiler_fail_next_capture_for_testing(void) {
    if (auto *owner = profiler()) {
        owner->fail_next_capture_for_testing();
    }
}

extern "C" bool dd_memory_profiler_start_for_testing(dd_memory_test_hook_failure_t failure) {
    auto *owner = profiler();
    return owner != nullptr && owner->start(true, failure);
}

extern "C" void dd_memory_profiler_record_for_testing(const dd_memory_live_sample_t *sample) {
    if (auto *owner = profiler()) {
        owner->test_record(sample);
    }
}

extern "C" void dd_memory_profiler_remove_for_testing(const void *address) {
    if (auto *owner = profiler()) {
        owner->test_remove(address);
    }
}

extern "C" void *dd_memory_profiler_allocate_objc_for_testing(void) {
    static Class fixture = [] {
        Class type = objc_allocateClassPair(objc_getClass("NSObject"),
                                           "DDMemoryProfilerNativeLargeFixture", 0);
        if (type == nullptr) {
            return static_cast<Class>(nullptr);
        }
        if (!class_addIvar(type, "payload", 16ULL * 1024ULL * 1024ULL, 3, "[16777216c]")) {
            objc_disposeClassPair(type);
            return static_cast<Class>(nullptr);
        }
        objc_registerClassPair(type);
        return type;
    }();
    using Allocate = void *(*)(Class, SEL);
    return fixture == nullptr ? nullptr :
        reinterpret_cast<Allocate>(objc_msgSend)(fixture, sel_registerName("alloc"));
}

extern "C" void dd_memory_profiler_release_objc_for_testing(void *object) {
    using Release = void (*)(void *, SEL);
    reinterpret_cast<Release>(objc_msgSend)(object, sel_registerName("release"));
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH && !TARGET_OS_OSX
