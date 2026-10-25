/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include "memory_profiler_testing.h"
#include "objc_alloc_hook.h"
#include "poisson_allocation_sampler.h"
#include "swift_alloc_hook.h"

#include <CoreFoundation/CoreFoundation.h>
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
    if (sample_rate < 100) {
        const double random = static_cast<double>(arc4random()) /
                              (static_cast<double>(UINT32_MAX) + 1.0);
        if (random * 100 >= sample_rate) {
            return;
        }
    }
    dd_memory_profiler_start();
}

class MemoryProfiler;
MemoryProfiler *observer_owner = nullptr;

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

class ObservationScope {
public:
    explicit ObservationScope(bool &observing) : observing_(observing), entered_(!observing) {
        if (entered_) {
            observing_ = true;
        }
    }
    ~ObservationScope() {
        if (entered_) {
            observing_ = false;
        }
    }
    ObservationScope(const ObservationScope &) = delete;
    ObservationScope &operator=(const ObservationScope &) = delete;
    ObservationScope(ObservationScope &&) = delete;
    ObservationScope &operator=(ObservationScope &&) = delete;
    bool entered() const { return entered_; }

private:
    bool &observing_;
    bool entered_;
};

class MemoryProfiler {
public:
    MemoryProfiler() = default;
    ~MemoryProfiler() = default;
    MemoryProfiler(const MemoryProfiler &) = delete;
    MemoryProfiler &operator=(const MemoryProfiler &) = delete;
    MemoryProfiler(MemoryProfiler &&) = delete;
    MemoryProfiler &operator=(MemoryProfiler &&) = delete;

    bool start(bool testing = false, uint32_t failed_hook = 0);
    void pause();
    void resume();
    void stop();
    bool running() const { return running_.load(std::memory_order_acquire); }
    bool paused() const {
        return running() && (allocation_epoch_.load(std::memory_order_acquire) & 1U) == 0;
    }
    int64_t windowStartTime() {
        std::lock_guard<std::mutex> lock(lifecycle_mutex_);
        return running() ? window_start_wall_ : 0;
    }
    dd_memory_capture_status_t capture(dd_memory_capture_t *capture);
    void allocation(const void *address, uint64_t size, const char *class_name,
                    const HeapMetadata *metadata, dd_swift_class_name_resolver_t resolver);
    void deallocation(const void *address);
#if defined(DEBUG)
    void configureForTesting(uint32_t failed_hook);
    void resetForTesting();
    void failNextCaptureForTesting();
    dd_memory_profiler_test_capture_diagnostics_t captureDiagnosticsForTesting();
    void testRecord(const dd_memory_live_sample_t *sample);
    void testRemove(const void *address);
#endif

private:
    bool beginSelected(uint64_t epoch);
    void endSelected();
    void disableAllocations();
    void stopLocked();
    void notifyDrain();
    dd_memory_capture_status_t captureLocked(dd_memory_capture_t *capture);
#if defined(DEBUG)
    void recordCaptureForTesting(dd_memory_capture_status_t status,
                                 const dd_memory_capture_t *capture);
    bool beginTestObservation();
    void endTestObservation();
    void drainTestObservations();
#endif

    std::mutex lifecycle_mutex_;
    std::mutex drain_mutex_;
    std::condition_variable drained_;
    std::atomic<bool> running_{false};
    // Odd means allocating. Every transition has a distinct epoch, so a
    // pre-pause sampler callback cannot be admitted after resume.
    std::atomic<uint64_t> allocation_epoch_{0};
    std::atomic<uint64_t> selected_in_flight_{0};
    std::atomic<uint64_t> sampler_session_{0};
    dd_memory_allocation_window_t *window_ = nullptr;
    uint64_t generation_ = 0;
    uint64_t previous_occupancy_ = 0;
    int64_t window_start_monotonic_ = 0;
    int64_t window_start_wall_ = 0;
    int64_t paused_end_ = 0;
    inline static thread_local bool observing_ = false;
#if defined(DEBUG)
    static constexpr uint64_t kTestEnabled = uint64_t{1} << 63U;
    std::atomic<uint64_t> test_observations_{0};
    bool configured_testing_ = false;
    uint32_t configured_failed_hook_ = DD_MEMORY_TEST_HOOKS_SUCCEED;
    bool fail_next_capture_ = false;
    dd_memory_profiler_test_capture_diagnostics_t capture_diagnostics_{};
#endif
};

// Initialized only through lifecycle entry points, before installing callbacks.
// Intentionally process-lived: runtime trampolines can outlive SDK teardown.
MemoryProfiler *profiler() {
    static MemoryProfiler *const instance = new (std::nothrow) MemoryProfiler();
    return instance;
}

bool MemoryProfiler::start(bool testing, uint32_t failed_hook) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    if (running()) {
        return true;
    }
#if defined(DEBUG)
    if (configured_testing_) {
        testing = true;
        failed_hook = configured_failed_hook_;
    }
#endif
    if (sampler_session_.load(std::memory_order_relaxed) == std::numeric_limits<uint64_t>::max() ||
        !clock_origin(window_start_monotonic_, window_start_wall_)) {
        return false;
    }
    window_ = dd_memory_allocation_window_create();
    if (window_ == nullptr) {
        return false;
    }
    generation_ = dd_memory_allocation_window_start(window_);
    if (generation_ == 0) {
        dd_memory_allocation_window_destroy(window_);
        window_ = nullptr;
        return false;
    }
    sampler_session_.fetch_add(1, std::memory_order_relaxed);
    previous_occupancy_ = 0;
    paused_end_ = 0;
    observer_owner = this;
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
    bool swift_ready = swift_status == DD_SWIFT_ALLOC_HOOK_OK ||
                       swift_status == DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED;
#if defined(DEBUG)
    swift_ready = swift_ready && failed_hook != DD_MEMORY_TEST_SWIFT_HOOK_FAILS;
#endif
    bool objc_ready = false;
    if (swift_ready) {
        const auto objc_status = dd_objc_alloc_hook_start(objc_allocation, deallocation);
        objc_ready = objc_status == DD_OBJC_ALLOC_HOOK_OK ||
                     objc_status == DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED;
#if defined(DEBUG)
        objc_ready = objc_ready && failed_hook != DD_MEMORY_TEST_OBJC_HOOK_FAILS;
#endif
    }
    if (!swift_ready || !objc_ready) {
        stopLocked();
        return false;
    }
#if defined(DEBUG)
    if (testing) {
        test_observations_.store(kTestEnabled, std::memory_order_release);
    }
#endif
    running_.store(true, std::memory_order_release);
    allocation_epoch_.fetch_add(1);
    return true;
}

void MemoryProfiler::notifyDrain() {
    std::lock_guard<std::mutex> lock(drain_mutex_);
    drained_.notify_all();
}

bool MemoryProfiler::beginSelected(uint64_t epoch) {
    selected_in_flight_.fetch_add(1);
    if (allocation_epoch_.load() == epoch && (epoch & 1U) != 0) {
        return true;
    }
    endSelected();
    return false;
}

void MemoryProfiler::endSelected() {
    if (selected_in_flight_.fetch_sub(1) == 1 &&
        (allocation_epoch_.load() & 1U) == 0) {
        notifyDrain();
    }
}

void MemoryProfiler::disableAllocations() {
    if ((allocation_epoch_.load() & 1U) != 0) {
        allocation_epoch_.fetch_add(1);
    }
    std::unique_lock<std::mutex> lock(drain_mutex_);
    drained_.wait(lock, [this] { return selected_in_flight_.load() == 0; });
}

void MemoryProfiler::pause() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    if (!running() || paused()) {
        return;
    }
    disableAllocations();
    paused_end_ = static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
}

void MemoryProfiler::resume() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    if (!paused()) {
        return;
    }
    int64_t monotonic = 0;
    int64_t wall = 0;
    if (!clock_origin(monotonic, wall)) {
        return;
    }
    window_start_monotonic_ = monotonic;
    window_start_wall_ = wall;
    paused_end_ = 0;
    allocation_epoch_.fetch_add(1);
}

void MemoryProfiler::stopLocked() {
    if (window_ == nullptr) {
        return;
    }
    disableAllocations();
    // Each hook drains its entire observer callback, including lock-free free
    // misses. The recorder can be destroyed only after both drains finish.
    dd_swift_alloc_hook_stop();
    dd_objc_alloc_hook_stop();
#if defined(DEBUG)
    drainTestObservations();
#endif
    running_.store(false, std::memory_order_release);
    dd_memory_allocation_window_stop(window_);
    dd_memory_allocation_window_destroy(window_);
    window_ = nullptr;
    generation_ = 0;
    window_start_wall_ = 0;
    window_start_monotonic_ = 0;
    paused_end_ = 0;
}

void MemoryProfiler::stop() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    stopLocked();
}

dd_memory_capture_status_t MemoryProfiler::capture(dd_memory_capture_t *capture) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    const auto status = captureLocked(capture);
#if defined(DEBUG)
    recordCaptureForTesting(status, capture);
#endif
    return status;
}

dd_memory_capture_status_t MemoryProfiler::captureLocked(dd_memory_capture_t *capture) {
    if (capture == nullptr) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    *capture = {};
#if defined(DEBUG)
    if (fail_next_capture_) {
        fail_next_capture_ = false;
        return DD_MEMORY_CAPTURE_FAILED;
    }
#endif
    if (!running()) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    const int64_t end = paused() ? paused_end_ :
        static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
    if (end < window_start_monotonic_ ||
        !dd_memory_allocation_window_close(window_, generation_)) {
        return DD_MEMORY_CAPTURE_FAILED;
    }
    const auto diagnostics = dd_memory_allocation_window_closed_diagnostics(window_);
    capture->aggregation = dd_memory_allocation_window_view(window_);
    capture->time_nanos = window_start_wall_;
    capture->duration_nanos = end - window_start_monotonic_;
    window_start_wall_ += capture->duration_nanos;
    window_start_monotonic_ = end;
    const bool idle = diagnostics.recorded_allocations == 0 &&
                      diagnostics.dropped_alloc_records == 0 &&
                      diagnostics.live_set.occupancy == previous_occupancy_;
    previous_occupancy_ = diagnostics.live_set.occupancy;
    return idle ? DD_MEMORY_CAPTURE_IDLE : DD_MEMORY_CAPTURE_READY;
}

void MemoryProfiler::allocation(
    const void *address, uint64_t size, const char *class_name,
    const HeapMetadata *metadata, dd_swift_class_name_resolver_t resolver) {
    const uint64_t epoch = allocation_epoch_.load(std::memory_order_acquire);
    if ((epoch & 1U) == 0) {
        return;
    }
    ObservationScope scope(observing_);
    if (!scope.entered()) {
        return;
    }
    thread_local dd::profiler::poisson_allocation_sampler sampler;
    const auto selected = sampler.sample(size, sampler_session_.load(std::memory_order_relaxed));
    if (selected.object_weight == 0 || !beginSelected(epoch)) {
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
    dd_memory_allocation_window_record(window_, generation_, &sample);
    endSelected();
}

void MemoryProfiler::deallocation(const void *address) {
    ObservationScope scope(observing_);
    if (scope.entered()) {
        dd_memory_allocation_window_remove(window_, generation_, address);
    }
}

#if defined(DEBUG)
void MemoryProfiler::configureForTesting(uint32_t failed_hook) {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    stopLocked();
    configured_testing_ = true;
    configured_failed_hook_ = failed_hook;
    fail_next_capture_ = false;
    capture_diagnostics_ = {};
}

void MemoryProfiler::resetForTesting() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    stopLocked();
    configured_testing_ = false;
    configured_failed_hook_ = DD_MEMORY_TEST_HOOKS_SUCCEED;
    fail_next_capture_ = false;
    capture_diagnostics_ = {};
}

void MemoryProfiler::failNextCaptureForTesting() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    fail_next_capture_ = true;
}

dd_memory_profiler_test_capture_diagnostics_t MemoryProfiler::captureDiagnosticsForTesting() {
    std::lock_guard<std::mutex> lock(lifecycle_mutex_);
    return capture_diagnostics_;
}

void MemoryProfiler::recordCaptureForTesting(dd_memory_capture_status_t status,
                                           const dd_memory_capture_t *capture) {
    const uint64_t captures_count = capture_diagnostics_.captures_count + 1;
    const uint64_t ready_count = capture_diagnostics_.ready_count +
        (status == DD_MEMORY_CAPTURE_READY ? 1 : 0);
    const uint64_t idle_count = capture_diagnostics_.idle_count +
        (status == DD_MEMORY_CAPTURE_IDLE ? 1 : 0);
    capture_diagnostics_ = {};
    capture_diagnostics_.captures_count = captures_count;
    capture_diagnostics_.ready_count = ready_count;
    capture_diagnostics_.idle_count = idle_count;
    capture_diagnostics_.last_status = status;
    if (status == DD_MEMORY_CAPTURE_FAILED || capture == nullptr) {
        return;
    }
    capture_diagnostics_.time_nanos = capture->time_nanos;
    capture_diagnostics_.duration_nanos = capture->duration_nanos;
    capture_diagnostics_.sample_count = capture->aggregation.count;
    for (size_t index = 0; index < capture->aggregation.count; ++index) {
        const auto &sample = capture->aggregation.samples[index];
        capture_diagnostics_.alloc_objects += sample.alloc_objects;
        capture_diagnostics_.alloc_space += sample.alloc_space;
        capture_diagnostics_.inuse_objects += sample.inuse_objects;
        capture_diagnostics_.inuse_space += sample.inuse_space;
    }
}

bool MemoryProfiler::beginTestObservation() {
    uint64_t state = test_observations_.load(std::memory_order_acquire);
    while ((state & kTestEnabled) != 0) {
        if (test_observations_.compare_exchange_weak(state, state + 1,
                                                    std::memory_order_acq_rel)) {
            return true;
        }
    }
    return false;
}

void MemoryProfiler::endTestObservation() {
    const uint64_t prior = test_observations_.fetch_sub(1, std::memory_order_acq_rel);
    if ((prior & ~kTestEnabled) == 1 && (prior & kTestEnabled) == 0) {
        notifyDrain();
    }
}

void MemoryProfiler::drainTestObservations() {
    test_observations_.fetch_and(~kTestEnabled, std::memory_order_acq_rel);
    std::unique_lock<std::mutex> lock(drain_mutex_);
    drained_.wait(lock, [this] { return test_observations_.load(std::memory_order_acquire) == 0; });
}

void MemoryProfiler::testRecord(const dd_memory_live_sample_t *sample) {
    if (!beginTestObservation()) {
        return;
    }
    const uint64_t epoch = allocation_epoch_.load(std::memory_order_acquire);
    ObservationScope scope(observing_);
    if (scope.entered() && beginSelected(epoch)) {
        dd_memory_allocation_window_record(window_, generation_, sample);
        endSelected();
    }
    endTestObservation();
}

void MemoryProfiler::testRemove(const void *address) {
    if (!beginTestObservation()) {
        return;
    }
    deallocation(address);
    endTestObservation();
}
#endif

void observe_swift_allocation(
    const void *address, uint64_t size, const HeapMetadata *metadata,
    dd_swift_class_name_resolver_t resolver) {
    observer_owner->allocation(address, size, nullptr, metadata, resolver);
}

void observe_objc_allocation(const void *address, uint64_t size, const char *class_name) {
    observer_owner->allocation(address, size, class_name, nullptr, nullptr);
}

void observe_deallocation(const void *address) {
    observer_owner->deallocation(address);
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

extern "C" bool dd_memory_profiler_start(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->start();
}

extern "C" bool dd_memory_profiler_is_running(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->running();
}

extern "C" bool dd_memory_profiler_is_paused(void) {
    auto *owner = profiler();
    return owner != nullptr && owner->paused();
}

extern "C" int64_t dd_memory_profiler_window_start_time_nanos(void) {
    auto *owner = profiler();
    return owner == nullptr ? 0 : owner->windowStartTime();
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
        owner->configureForTesting(failure);
    }
}

extern "C" void dd_memory_profiler_reset_for_testing(void) {
    if (auto *owner = profiler()) {
        owner->resetForTesting();
    }
}

extern "C" dd_memory_profiler_test_capture_diagnostics_t dd_memory_profiler_capture_diagnostics_for_testing(void) {
    auto *owner = profiler();
    return owner == nullptr ? dd_memory_profiler_test_capture_diagnostics_t{} :
                             owner->captureDiagnosticsForTesting();
}

extern "C" void dd_memory_profiler_fail_next_capture_for_testing(void) {
    if (auto *owner = profiler()) {
        owner->failNextCaptureForTesting();
    }
}

extern "C" bool dd_memory_profiler_start_for_testing(dd_memory_test_hook_failure_t failure) {
    auto *owner = profiler();
    return owner != nullptr && owner->start(true, failure);
}

extern "C" void dd_memory_profiler_record_for_testing(const dd_memory_live_sample_t *sample) {
    if (auto *owner = profiler()) {
        owner->testRecord(sample);
    }
}

extern "C" void dd_memory_profiler_remove_for_testing(const void *address) {
    if (auto *owner = profiler()) {
        owner->testRemove(address);
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

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
