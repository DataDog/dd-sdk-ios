/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include "objc_alloc_hook.h"
#include "poisson_allocation_sampler.h"
#include "swift_alloc_hook.h"
#if DEBUG
#include "memory_profiler_testing.h"
#endif

#include <atomic>
#include <execinfo.h>
#include <mutex>
#include <new>

namespace {

// Covers cross-runtime reentry as well as allocations made while capturing a
// stack. Hook-local guards alone do not cover Obj-C -> Swift -> Obj-C reentry.
thread_local bool observing = false;
#if DEBUG
thread_local bool force_next_sample = false;
thread_local uint64_t forced_generation = 0;
#endif

class ObservationGuard {
public:
    ObservationGuard() : previous(observing) { observing = true; }
    ~ObservationGuard() { observing = previous; }
    ObservationGuard(const ObservationGuard &) = delete;
    ObservationGuard &operator=(const ObservationGuard &) = delete;
private:
    bool previous;
};

class MemoryProfiler {
public:
    bool start();
    void stop();
    bool is_running() const { return running.load(std::memory_order_acquire); }
    bool capture(bool drain_allocations, dd_memory_aggregation_view_t *out_view);
    dd_memory_allocation_window_diagnostics_t diagnostics();
    void observe_allocation(const void *address, uint64_t size,
                            const char *class_name, const HeapMetadata *metadata,
                            dd_swift_class_name_resolver_t resolver,
                            dd_memory_live_sample_source_t source);
    void observe_deallocation(const void *address);
#if DEBUG
    void reset();
    bool record_sample(const dd_memory_live_sample_t *sample, uint64_t token);
    uint64_t session_generation() const { return generation.load(std::memory_order_acquire); }
    std::atomic<bool> force_start_failure{false};
    std::atomic<bool> force_capture_failure{false};
    std::atomic<uint64_t> sampled_count{0};
#endif

private:
    // Only lifecycle/capture/diagnostic callers take this mutex. Allocation and
    // deallocation observers use the reviewed window's own synchronization.
    std::mutex lifecycle_mutex;
    std::atomic<bool> running{false};
    std::atomic<uint64_t> generation{0};
    // Allocated before observation is enabled, retained for the process lifetime.
    // stop drains both hooks before clearing, so observers cannot cross restarts.
    dd_memory_allocation_window_t *window = nullptr;
    void stop_locked();
};

MemoryProfiler &profiler() {
    // The forwarding trampolines can run during static destruction. Like their
    // state, the recorder owner remains valid until the process exits.
    alignas(MemoryProfiler) static unsigned char storage[sizeof(MemoryProfiler)];
    static auto *instance = new (storage) MemoryProfiler();
    return *instance;
}

void observe_objc_allocation(const void *address, uint64_t size, const char *class_name) {
    profiler().observe_allocation(address, size, class_name, nullptr, nullptr,
                                  DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC);
}

void observe_swift_allocation(const void *address, uint64_t size,
                              const HeapMetadata *metadata,
                              dd_swift_class_name_resolver_t resolver) {
    profiler().observe_allocation(address, size, nullptr, metadata, resolver,
                                  DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT);
}

void observe_object_deallocation(const void *address) {
    profiler().observe_deallocation(address);
}

bool MemoryProfiler::start() {
    ObservationGuard observation_guard;
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (is_running()) {
        return true;
    }
#if DEBUG
    if (force_start_failure.load(std::memory_order_acquire)) {
        return false;
    }
#endif
    if (window == nullptr) {
        window = dd_memory_allocation_window_create();
    }
    if (window == nullptr) {
        return false;
    }
    const uint64_t token = dd_memory_allocation_window_start(window);
    generation.store(token, std::memory_order_release);
    if (token == 0) {
        return false;
    }
#if DEBUG
    sampled_count.store(0, std::memory_order_relaxed);
#endif
    const auto objc_status = dd_objc_alloc_hook_start(observe_objc_allocation, observe_object_deallocation);
    const bool objc_started = objc_status == DD_OBJC_ALLOC_HOOK_OK ||
                              objc_status == DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED;
    if (!objc_started) {
        stop_locked();
        return false;
    }
    const auto swift_status = dd_swift_alloc_hook_start(observe_swift_allocation, observe_object_deallocation);
    const bool swift_started = swift_status == DD_SWIFT_ALLOC_HOOK_OK ||
                               swift_status == DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED;
    if (!swift_started) {
        stop_locked();
        return false;
    }
    // No observer could record the install's own allocations while false.
    running.store(true, std::memory_order_release);
    return true;
}

void MemoryProfiler::stop_locked() {
    running.store(false, std::memory_order_release);
    dd_objc_alloc_hook_stop();
    dd_swift_alloc_hook_stop();
    if (window != nullptr) {
        // A terminal stop must discard data for revoked consent or a sampled-out
        // session. Hooks are drained before the reviewed store is reset.
        dd_memory_allocation_window_stop(window);
        generation.store(dd_memory_allocation_window_start(window), std::memory_order_release);
        dd_memory_allocation_window_stop(window);
    }
#if DEBUG
    sampled_count.store(0, std::memory_order_relaxed);
#endif
}

void MemoryProfiler::stop() {
    ObservationGuard observation_guard;
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    stop_locked();
}

void MemoryProfiler::observe_allocation(
    const void *address, uint64_t size, const char *class_name,
    const HeapMetadata *metadata, dd_swift_class_name_resolver_t resolver,
    dd_memory_live_sample_source_t source) {
    if (observing || address == nullptr || size == 0 || !is_running()) {
        return;
    }
    ObservationGuard observation_guard;
    const uint64_t token = generation.load(std::memory_order_acquire);
    // Constructing the thread-confined RNG is a one-time cost on this thread,
    // fenced against reentry. sample() itself never allocates or synchronizes.
    thread_local dd::profiler::poisson_allocation_sampler sampler;
    double weight = sampler.sample(size, token).object_weight;
#if DEBUG
    if (force_next_sample) {
        force_next_sample = false;
        if (forced_generation == token) {
            weight = 1.0;
        }
    }
#endif
    if (weight == 0) {
        return;
    }
    dd_memory_live_sample_t sample{};
    sample.address = address;
    sample.size = size;
    sample.weight = weight;
    sample.class_name = class_name;
    sample.swift_metadata = metadata;
    sample.swift_name_resolver = resolver;
    sample.source = source;
    void *frames[DD_MEMORY_LIVE_SET_MAX_FRAMES];
    const int count = backtrace(frames, DD_MEMORY_LIVE_SET_MAX_FRAMES);
    for (int i = 0; i < count; ++i) {
        sample.frames[i] = reinterpret_cast<uintptr_t>(frames[i]);
    }
    sample.frame_count = count > 0 ? static_cast<uint32_t>(count) : 0;
    dd_memory_allocation_window_record(window, token, &sample);
#if DEBUG
    sampled_count.fetch_add(1, std::memory_order_relaxed);
#endif
}

void MemoryProfiler::observe_deallocation(const void *address) {
    if (observing || address == nullptr || !is_running()) {
        return;
    }
    ObservationGuard observation_guard;
    dd_memory_allocation_window_remove(window, generation.load(std::memory_order_acquire), address);
}

bool MemoryProfiler::capture(bool drain_allocations, dd_memory_aggregation_view_t *out_view) {
    if (out_view == nullptr) {
        return false;
    }
    *out_view = {};
    ObservationGuard observation_guard;
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (!is_running()) {
        return false;
    }
#if DEBUG
    if (force_capture_failure.load(std::memory_order_acquire)) {
        return false;
    }
#endif
    const uint64_t token = generation.load(std::memory_order_acquire);
    const bool captured = drain_allocations
        ? dd_memory_allocation_window_close(window, token)
        : dd_memory_allocation_window_snapshot_live(window, token);
    if (captured) {
        *out_view = dd_memory_allocation_window_view(window);
    }
    return captured;
}

dd_memory_allocation_window_diagnostics_t MemoryProfiler::diagnostics() {
    ObservationGuard observation_guard;
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    return dd_memory_allocation_window_diagnostics(window);
}

#if DEBUG
void MemoryProfiler::reset() {
    ObservationGuard observation_guard;
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    stop_locked();
    force_start_failure.store(false, std::memory_order_release);
    force_capture_failure.store(false, std::memory_order_release);
    force_next_sample = false;
    forced_generation = 0;
}

bool MemoryProfiler::record_sample(const dd_memory_live_sample_t *sample, uint64_t token) {
    ObservationGuard observation_guard;
    std::lock_guard<std::mutex> lock(lifecycle_mutex);
    if (!is_running()) {
        return false;
    }
    const auto result = dd_memory_allocation_window_record(window, token, sample);
    if (result != DD_MEMORY_LIVE_SET_STALE_GENERATION &&
        result != DD_MEMORY_LIVE_SET_INVALID_SAMPLE) {
        sampled_count.fetch_add(1, std::memory_order_relaxed);
    }
    return result == DD_MEMORY_LIVE_SET_INSERTED;
}
#endif

} // namespace

extern "C" bool dd_memory_profiler_start(void) { return profiler().start(); }
extern "C" void dd_memory_profiler_stop(void) { profiler().stop(); }
extern "C" bool dd_memory_profiler_is_running(void) { return profiler().is_running(); }
extern "C" bool dd_memory_profiler_capture(bool drain_allocations,
                                           dd_memory_aggregation_view_t *out_view) {
    return profiler().capture(drain_allocations, out_view);
}
extern "C" dd_memory_allocation_window_diagnostics_t dd_memory_profiler_diagnostics(void) {
    return profiler().diagnostics();
}

#if DEBUG
extern "C" void dd_memory_test_reset(void) { profiler().reset(); }
extern "C" void dd_memory_test_force_start_failure(bool enabled) {
    profiler().force_start_failure.store(enabled, std::memory_order_release);
}
extern "C" void dd_memory_test_force_capture_failure(bool enabled) {
    profiler().force_capture_failure.store(enabled, std::memory_order_release);
}
extern "C" void dd_memory_test_force_next_sample(void) {
    forced_generation = profiler().session_generation();
    force_next_sample = true;
}
extern "C" uint64_t dd_memory_test_sampled_count(void) {
    return profiler().sampled_count.load(std::memory_order_relaxed);
}
extern "C" uint64_t dd_memory_test_live_count(void) {
    return profiler().diagnostics().live_set.occupancy;
}
extern "C" uint64_t dd_memory_test_session_generation(void) {
    return profiler().session_generation();
}
extern "C" bool dd_memory_test_record_sample(const dd_memory_live_sample_t *sample, uint64_t token) {
    return profiler().record_sample(sample, token);
}
extern "C" bool dd_memory_test_insert_sample(const void *address, uint64_t size, uint64_t token) {
    dd_memory_live_sample_t sample{};
    sample.address = address;
    sample.size = size;
    sample.weight = 1.0;
    sample.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_UNKNOWN;
    return profiler().record_sample(&sample, token);
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
