/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_allocation_window.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <array>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <new>
#include <numeric>
#include <os/lock.h>
#include <type_traits>

namespace {

constexpr size_t kAllocationCapacity = DD_MEMORY_ALLOCATION_WINDOW_CAPACITY;
constexpr size_t kAggregationCapacity = DD_MEMORY_AGGREGATION_CAPACITY;
constexpr size_t kHashCapacity = 2 * kAggregationCapacity;
constexpr size_t kMaxClassNameBytes = DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES;
static_assert(kAggregationCapacity >= kAllocationCapacity + DD_MEMORY_LIVE_SET_CAPACITY,
              "aggregation storage must fit disjoint allocation and live keys");
static_assert((kHashCapacity & (kHashCapacity - 1)) == 0,
              "aggregation hash capacity must be a power of two");
static_assert(kAggregationCapacity < UINT32_MAX,
              "aggregation indices must fit in the hash index");

using ClassNameStorage = std::array<char, kMaxClassNameBytes>;

struct AllocationRecord {
    dd_memory_live_sample_t sample;
    ClassNameStorage class_name;
};

using AllocationLog = std::array<AllocationRecord, kAllocationCapacity>;

// Fixed buffers are inline with their owner and initialized before publication.
struct WindowStorage {
    std::array<AllocationLog, 2> allocations;
    std::array<dd_memory_aggregate_t, kAggregationCapacity> aggregates;
    std::array<ClassNameStorage, kAggregationCapacity> class_names;
    // Zero denotes an unused bucket; other values are aggregate indices + 1.
    std::array<uint32_t, kHashCapacity> hash_index;
};
static_assert(std::is_trivial<WindowStorage>::value,
              "window buffers must remain trivial for zero-initialized allocation");

bool valid_sample(const dd_memory_live_sample_t *sample) {
    return sample != nullptr &&
           reinterpret_cast<uintptr_t>(sample->address) > 1 &&
           sample->frame_count <= DD_MEMORY_LIVE_SET_MAX_FRAMES &&
           (sample->swift_metadata == nullptr) ==
               (sample->swift_name_resolver == nullptr) &&
           (sample->class_name == nullptr || sample->swift_metadata == nullptr) &&
           sample->source >= DD_MEMORY_LIVE_SAMPLE_SOURCE_UNKNOWN &&
           sample->source <= DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT &&
           std::isfinite(sample->weight) && sample->weight > 0 &&
           std::isfinite(static_cast<double>(sample->size) * sample->weight) &&
           static_cast<double>(sample->size) * sample->weight > 0;
}

uint64_t hash_word(uint64_t hash, uint64_t value) {
    // Use the SplitMix64 finalizer to mix the entire stack address, including
    // high bits used by tagged pointers, before combining it into the hash.
    value ^= value >> 30U;
    value *= 0xbf58476d1ce4e5b9ULL;
    value ^= value >> 27U;
    value *= 0x94d049bb133111ebULL;
    value ^= value >> 31U;
    return (hash ^ value) * 0x100000001b3ULL;
}

void copy_key(dd_memory_aggregation_key_t &key, const dd_memory_live_sample_t &sample) {
    key.class_name = sample.class_name;
    key.swift_metadata = sample.swift_metadata;
    key.swift_name_resolver = sample.swift_name_resolver;
    key.frame_count = sample.frame_count;
    key.source = sample.source;
    std::memcpy(key.frames, sample.frames, sample.frame_count * sizeof(sample.frames[0]));
}

size_t sample_key_bucket(const dd_memory_live_sample_t &sample) {
    uint64_t hash = hash_word(0xcbf29ce484222325ULL, sample.source);
    hash = hash_word(hash, sample.frame_count);
    hash = std::accumulate(std::begin(sample.frames), std::begin(sample.frames) + sample.frame_count,
                           hash, hash_word);
    if (sample.swift_metadata != nullptr) {
        hash = hash_word(hash, 1);
        hash = hash_word(hash, reinterpret_cast<uintptr_t>(sample.swift_metadata));
    } else if (sample.class_name != nullptr) {
        hash = hash_word(hash, 2);
        for (const char *character = sample.class_name; *character != '\0'; ++character) {
            hash = (hash ^ static_cast<unsigned char>(*character)) * 0x100000001b3ULL;
        }
    } else {
        hash = hash_word(hash, 0);
    }
    return static_cast<size_t>(hash) & (kHashCapacity - 1);
}

bool same_key(const dd_memory_aggregation_key_t &left,
              const dd_memory_live_sample_t &right) {
    if (left.source != right.source || left.frame_count != right.frame_count ||
        std::memcmp(left.frames, right.frames,
                    left.frame_count * sizeof(left.frames[0])) != 0) {
        return false;
    }
    if (left.swift_metadata != nullptr || right.swift_metadata != nullptr) {
        return left.swift_metadata == right.swift_metadata;
    }
    if (left.class_name == nullptr || right.class_name == nullptr) {
        return left.class_name == right.class_name;
    }
    return std::strcmp(left.class_name, right.class_name) == 0;
}

} // namespace

class dd_memory_allocation_window {
public:
    static dd_memory_allocation_window_t *create();
    void destroy();
    uint64_t start();
    void stop();
    dd_memory_live_insert_result_t record(
        uint64_t token, const dd_memory_live_sample_t *sample);
    bool remove(uint64_t token, const void *address) {
        // In particular, unsampled deallocations never acquire recorder_lock.
        return dd_memory_live_set_remove(live_set, token, address);
    }
    bool close(uint64_t token);
    dd_memory_aggregation_view_t view() const {
        return {storage.aggregates.data(), aggregate_count};
    }
    dd_memory_closed_window_diagnostics_t closed_diagnostics() const {
        return closed;
    }
    dd_memory_allocation_window_diagnostics_t diagnostics();

    dd_memory_allocation_window() = default;
    ~dd_memory_allocation_window() = default;
    dd_memory_allocation_window(const dd_memory_allocation_window &) = delete;
    dd_memory_allocation_window &operator=(const dd_memory_allocation_window &) = delete;
    dd_memory_allocation_window(dd_memory_allocation_window &&) = delete;
    dd_memory_allocation_window &operator=(dd_memory_allocation_window &&) = delete;

private:
    // Lock order is recorder_lock -> the live set's state lock. Deallocation
    // only takes the latter. Successful close captures the live set before
    // swapping logs, while records cannot cross that boundary.
    os_unfair_lock recorder_lock = OS_UNFAIR_LOCK_INIT;
    dd_memory_live_set_t *live_set = nullptr;
    dd_memory_live_snapshot_t *live_snapshot = nullptr;
    uint64_t storage_bytes = 0;
    uint64_t generation = 0;
    bool active = false;
    bool active_log = false;
    size_t recorded_count = 0;
    uint64_t peak_recorded_count = 0;
    uint64_t dropped_alloc_records = 0;
    uint64_t omitted_class_names = 0;
    // Serialized by the owner, independent of producer mutations.
    size_t aggregate_count = 0;
    dd_memory_closed_window_diagnostics_t closed{};
    WindowStorage storage{};

    class RecorderLockGuard {
    public:
        explicit RecorderLockGuard(dd_memory_allocation_window &window) : window(window) {
            os_unfair_lock_lock(&window.recorder_lock);
        }

        ~RecorderLockGuard() {
            os_unfair_lock_unlock(&window.recorder_lock);
        }

        RecorderLockGuard(const RecorderLockGuard &) = delete;
        RecorderLockGuard &operator=(const RecorderLockGuard &) = delete;
        RecorderLockGuard(RecorderLockGuard &&) = delete;
        RecorderLockGuard &operator=(RecorderLockGuard &&) = delete;

    private:
        dd_memory_allocation_window &window;
    };

    void clear_counters() {
        recorded_count = 0;
        peak_recorded_count = 0;
        dropped_alloc_records = 0;
        omitted_class_names = 0;
    }

    void aggregate(const dd_memory_live_sample_t &sample, bool allocation);
};

dd_memory_allocation_window_t *dd_memory_allocation_window::create() {
    void *allocation = std::calloc(1, sizeof(dd_memory_allocation_window_t));
    if (allocation == nullptr) {
        return nullptr;
    }
    dd_memory_live_set_t *live_set = dd_memory_live_set_create();
    dd_memory_live_snapshot_t *snapshot = dd_memory_live_snapshot_create();
    if (live_set == nullptr || snapshot == nullptr) {
        dd_memory_live_set_destroy(live_set);
        dd_memory_live_snapshot_destroy(snapshot);
        std::free(allocation);
        return nullptr;
    }
    // Establish C++ object lifetimes in zeroed storage. Optimized builds elide
    // redundant buffer initialization after calloc.
    auto *window = new (allocation) dd_memory_allocation_window_t;
    window->live_set = live_set;
    window->live_snapshot = snapshot;
    window->storage_bytes = sizeof(dd_memory_allocation_window_t) +
                            dd_memory_live_set_diagnostics(live_set).table_bytes +
                            dd_memory_live_snapshot_storage_bytes(snapshot);
    return window;
}

void dd_memory_allocation_window::destroy() {
    // The owner has already drained producers and readers.
    dd_memory_live_set_destroy(live_set);
    dd_memory_live_snapshot_destroy(live_snapshot);
    void *allocation = this;
    this->~dd_memory_allocation_window();
    std::free(allocation);
}

uint64_t dd_memory_allocation_window::start() {
    RecorderLockGuard lock(*this);
    active = false;
    generation = dd_memory_live_set_start(live_set);
    active_log = false;
    clear_counters();
    aggregate_count = 0;
    closed = {};
    active = generation != 0;
    return generation;
}

void dd_memory_allocation_window::stop() {
    RecorderLockGuard lock(*this);
    active = false;
    dd_memory_live_set_stop(live_set);
}

dd_memory_live_insert_result_t dd_memory_allocation_window::record(
    uint64_t token, const dd_memory_live_sample_t *sample) {
    if (!valid_sample(sample)) {
        return DD_MEMORY_LIVE_SET_INVALID_SAMPLE;
    }
    RecorderLockGuard lock(*this);
    if (!active || token != generation) {
        return DD_MEMORY_LIVE_SET_STALE_GENERATION;
    }

    if (recorded_count < kAllocationCapacity) {
        AllocationRecord &record = storage.allocations[active_log][recorded_count];
        record.sample = *sample;
        if (sample->class_name != nullptr) {
            const size_t length = strnlen(sample->class_name, kMaxClassNameBytes);
            if (length == kMaxClassNameBytes) {
                record.sample.class_name = nullptr;
                ++omitted_class_names;
            } else {
                std::memcpy(record.class_name.data(), sample->class_name, length + 1);
                record.sample.class_name = record.class_name.data();
            }
        }
        ++recorded_count;
        peak_recorded_count = recorded_count;
    } else {
        ++dropped_alloc_records;
    }
    // Admission loss here only affects inuse_*. Allocation records are already
    // owned by the window, even when this insert exhausts its bounded probe.
    return dd_memory_live_set_insert(live_set, token, sample);
}

bool dd_memory_allocation_window::close(uint64_t token) {
    aggregate_count = 0;
    closed = {};
    bool drained_log = false;
    size_t drained_count = 0;
    {
        RecorderLockGuard lock(*this);
        if (!active || token != generation ||
            !dd_memory_live_set_snapshot(live_set, token, live_snapshot)) {
            return false;
        }
        drained_log = active_log;
        drained_count = recorded_count;
        closed.recorded_allocations = recorded_count;
        closed.peak_recorded_allocations = peak_recorded_count;
        closed.dropped_alloc_records = dropped_alloc_records;
        closed.omitted_class_names = omitted_class_names;
        closed.live_set = dd_memory_live_snapshot_diagnostics(live_snapshot);
        active_log = !active_log;
        clear_counters();
    }

    // No producer accesses the drained log or snapshot. Keying, aggregation
    // and all eventual Swift name resolution happen outside recorder_lock.
    storage.hash_index.fill(0);
    for (size_t i = 0; i < drained_count; ++i) {
        aggregate(storage.allocations[drained_log][i].sample, true);
    }
    const dd_memory_live_snapshot_view_t live = dd_memory_live_snapshot_view(live_snapshot);
    for (size_t i = 0; i < live.count; ++i) {
        aggregate(live.samples[i], false);
    }
    return true;
}

void dd_memory_allocation_window::aggregate(
    const dd_memory_live_sample_t &sample, bool allocation) {
    const size_t start = sample_key_bucket(sample);
    for (size_t offset = 0; offset < kHashCapacity; ++offset) {
        const size_t bucket = (start + offset) & (kHashCapacity - 1);
        uint32_t &entry = storage.hash_index[bucket];
        size_t index = 0;
        if (entry == 0) {
            // At most allocation capacity + live capacity input records are
            // processed, so every input group has preallocated output space.
            index = aggregate_count++;
            dd_memory_aggregate_t &output = storage.aggregates[index];
            output = {};
            copy_key(output.key, sample);
            if (sample.class_name != nullptr) {
                const size_t length = std::strlen(sample.class_name);
                std::memcpy(storage.class_names[index].data(), sample.class_name, length + 1);
                output.key.class_name = storage.class_names[index].data();
            }
            entry = static_cast<uint32_t>(index + 1);
        } else {
            index = entry - 1;
            if (!same_key(storage.aggregates[index].key, sample)) {
                continue;
            }
        }
        dd_memory_aggregate_t &output = storage.aggregates[index];
        const double bytes = static_cast<double>(sample.size) * sample.weight;
        if (allocation) {
            output.alloc_objects += sample.weight;
            output.alloc_space += bytes;
        } else {
            output.inuse_objects += sample.weight;
            output.inuse_space += bytes;
        }
        return;
    }
}

dd_memory_allocation_window_diagnostics_t dd_memory_allocation_window::diagnostics() {
    RecorderLockGuard lock(*this);
    dd_memory_allocation_window_diagnostics_t result{};
    result.capacity = kAllocationCapacity;
    result.recorded_allocations = recorded_count;
    result.peak_recorded_allocations = peak_recorded_count;
    result.dropped_alloc_records = dropped_alloc_records;
    result.omitted_class_names = omitted_class_names;
    result.storage_bytes = storage_bytes;
    result.live_set = dd_memory_live_set_diagnostics(live_set);
    return result;
}

extern "C" dd_memory_allocation_window_t *dd_memory_allocation_window_create(void) {
    return dd_memory_allocation_window::create();
}

extern "C" void dd_memory_allocation_window_destroy(dd_memory_allocation_window_t *window) {
    if (window != nullptr) {
        window->destroy();
    }
}

extern "C" uint64_t dd_memory_allocation_window_start(dd_memory_allocation_window_t *window) {
    return window != nullptr ? window->start() : 0;
}

extern "C" void dd_memory_allocation_window_stop(dd_memory_allocation_window_t *window) {
    if (window != nullptr) {
        window->stop();
    }
}

extern "C" dd_memory_live_insert_result_t dd_memory_allocation_window_record(
    dd_memory_allocation_window_t *window, uint64_t generation,
    const dd_memory_live_sample_t *sample) {
    return window != nullptr ? window->record(generation, sample)
                             : DD_MEMORY_LIVE_SET_INVALID_SAMPLE;
}

extern "C" bool dd_memory_allocation_window_remove(
    dd_memory_allocation_window_t *window, uint64_t generation, const void *address) {
    return window != nullptr && window->remove(generation, address);
}

extern "C" bool dd_memory_allocation_window_close(
    dd_memory_allocation_window_t *window, uint64_t generation) {
    return window != nullptr && window->close(generation);
}

extern "C" dd_memory_aggregation_view_t dd_memory_allocation_window_view(
    const dd_memory_allocation_window_t *window) {
    return window != nullptr ? window->view() : dd_memory_aggregation_view_t{};
}

extern "C" dd_memory_closed_window_diagnostics_t dd_memory_allocation_window_closed_diagnostics(
    const dd_memory_allocation_window_t *window) {
    return window != nullptr ? window->closed_diagnostics()
                             : dd_memory_closed_window_diagnostics_t{};
}

extern "C" dd_memory_allocation_window_diagnostics_t dd_memory_allocation_window_diagnostics(
    dd_memory_allocation_window_t *window) {
    return window != nullptr ? window->diagnostics()
                             : dd_memory_allocation_window_diagnostics_t{};
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
