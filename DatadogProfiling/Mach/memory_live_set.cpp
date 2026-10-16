/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_live_set.h"
#include "memory_live_set_testing.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <atomic>
#include <cstring>
#include <new>
#include <os/lock.h>
#include <sys/mman.h>
#include <type_traits>
#include <unistd.h>

namespace {

constexpr size_t kCapacity = DD_MEMORY_LIVE_SET_CAPACITY;
constexpr size_t kMaxProbe = DD_MEMORY_LIVE_SET_MAX_PROBE;
constexpr size_t kMaxClassNameBytes = DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES;
constexpr size_t kMaxSnapshotNameBytes = kCapacity * kMaxClassNameBytes;
constexpr uintptr_t kEmpty = 0;
constexpr uintptr_t kTombstone = 1;
static_assert((kCapacity & (kCapacity - 1)) == 0, "capacity must be a power of two");
static_assert(kMaxProbe <= kCapacity, "probe bound must fit in the table");
static_assert(sizeof(std::atomic<uintptr_t>) == sizeof(uintptr_t),
              "address index must have pointer-sized entries");

struct Slot {
    dd_memory_live_sample_t sample{};
    char class_name_storage[kMaxClassNameBytes]{};

    bool class_name_bytes(size_t &bytes) const {
        bytes = 0;
        if (sample.class_name == nullptr) {
            return true;
        }
        const size_t length = strnlen(sample.class_name, kMaxClassNameBytes);
        if (length == kMaxClassNameBytes) {
            return false;
        }
        bytes = length + 1;
        return true;
    }
};

// Default-initialize this POD in mmap storage without writing unused pages.
// Only records published through a nonempty view are read by consumers.
struct SnapshotStorage {
    dd_memory_live_sample_t samples[kCapacity];
    char class_names[kMaxSnapshotNameBytes];
};
static_assert(std::is_trivial<SnapshotStorage>::value,
              "snapshot storage must remain trivial for lazy mmap initialization");

void update_peak(std::atomic<uint64_t> &peak, uint64_t value) {
    uint64_t current = peak.load(std::memory_order_relaxed);
    while (current < value &&
           !peak.compare_exchange_weak(current, value, std::memory_order_relaxed)) {}
}

size_t bucket_for(uintptr_t address) {
    uint64_t value = static_cast<uint64_t>(address >> 4U);
    value ^= value >> 30U;
    value *= 0xbf58476d1ce4e5b9ULL;
    value ^= value >> 27U;
    value *= 0x94d049bb133111ebULL;
    value ^= value >> 31U;
    return static_cast<size_t>(value) & (kCapacity - 1);
}

size_t mapped_bytes(size_t bytes) {
    const size_t page_size = static_cast<size_t>(getpagesize());
    return ((bytes + page_size - 1) / page_size) * page_size;
}

} // namespace

struct dd_memory_live_snapshot {
    static dd_memory_live_snapshot_t *create();
    void destroy();
    dd_memory_live_snapshot_view_t view() const {
        return {storage->samples, count};
    }
    void clear() {
        count = 0;
    }

    dd_memory_live_snapshot() = default;
    ~dd_memory_live_snapshot() = default;
    dd_memory_live_snapshot(const dd_memory_live_snapshot &) = delete;
    dd_memory_live_snapshot &operator=(const dd_memory_live_snapshot &) = delete;
    dd_memory_live_snapshot(dd_memory_live_snapshot &&) = delete;
    dd_memory_live_snapshot &operator=(dd_memory_live_snapshot &&) = delete;

private:
    friend struct dd_memory_live_set;

    SnapshotStorage *storage = nullptr;
    size_t count = 0;
    uint64_t storage_bytes = 0;

    dd_memory_live_sample_t &sample_at(size_t index) {
        return *(storage->samples + index);
    }
};
static_assert(sizeof(dd_memory_live_snapshot_t) % alignof(SnapshotStorage) == 0,
              "snapshot buffers must follow an aligned snapshot header");

dd_memory_live_snapshot_t *dd_memory_live_snapshot::create() {
    const size_t allocation_size =
        sizeof(dd_memory_live_snapshot_t) + sizeof(SnapshotStorage);
    void *mapping = mmap(nullptr, allocation_size,
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mapping == MAP_FAILED) {
        return nullptr;
    }
    auto *snapshot = new (mapping) dd_memory_live_snapshot_t();
    void *buffer_storage = static_cast<char *>(mapping) + sizeof(dd_memory_live_snapshot_t);
    snapshot->storage = new (buffer_storage) SnapshotStorage;
    snapshot->storage_bytes = mapped_bytes(allocation_size);
    return snapshot;
}

void dd_memory_live_snapshot::destroy() {
    void *mapping = this;
    const size_t allocation_size = storage_bytes;
    storage->~SnapshotStorage();
    this->~dd_memory_live_snapshot();
    munmap(mapping, allocation_size);
}

struct dd_memory_live_set {
    static dd_memory_live_set_t *create();
    void destroy();
    uint64_t start();
    void stop();
    dd_memory_live_insert_result_t insert(uint64_t token,
                                          const dd_memory_live_sample_t *sample);
    template <bool record_probe_length = false>
    bool remove(uint64_t token, const void *pointer,
                size_t *probe_length = nullptr);
    bool snapshot(uint64_t token, dd_memory_live_snapshot_t *snapshot);
    dd_memory_live_set_diagnostics_t diagnostics() const;
    void override_occupancy_for_testing(uint64_t value);

private:
    // state_lock protects sample storage and serializes lifecycle changes,
    // inserts, successful removals and snapshots. The compact atomic address
    // index and atomic lifecycle fields allow misses to probe without the lock;
    // hits recheck the generation and address after acquiring it.
    // Within a generation, removal creates tombstones; only start() restores
    // kEmpty. This preserves probe chains, allowing lookups to stop at kEmpty.
    // Compaction must quiesce probes and rebuild chains before making entries empty.
    os_unfair_lock state_lock = OS_UNFAIR_LOCK_INIT;
    Slot *slots = nullptr;
    std::atomic<uintptr_t> addresses[kCapacity]{};
    std::atomic<bool> active{false};
    std::atomic<uint64_t> generation{0};
    // Counters remain atomic so diagnostics can read without state_lock.
    // Those reads may reflect different instants; snapshots hold the lock
    // to capture one coherent view.
    std::atomic<uint64_t> generation_transitions{0};
    std::atomic<uint64_t> occupancy{0};
    std::atomic<uint64_t> peak_occupancy{0};
    std::atomic<uint64_t> tombstones{0};
    std::atomic<uint64_t> peak_tombstones{0};
    std::atomic<uint64_t> dropped_samples{0};
    std::atomic<uint64_t> duplicate_samples{0};
    std::atomic<uint64_t> omitted_class_names{0};
    std::atomic<uint64_t> stale_generation_rejections{0};
    std::atomic<uint64_t> snapshot_failures{0};
    std::atomic<uint64_t> probe_count{0};
    std::atomic<uint64_t> total_probe_length{0};
    std::atomic<uint64_t> max_probe_length{0};
    std::atomic<uint64_t> snapshot_bytes_high_water{0};
    std::atomic<bool> reached_admission_limit{false};

    class StateLockGuard {
    public:
        explicit StateLockGuard(dd_memory_live_set &table) : table(table) {
            os_unfair_lock_lock(&table.state_lock);
        }

        ~StateLockGuard() {
            os_unfair_lock_unlock(&table.state_lock);
        }

        StateLockGuard(const StateLockGuard &) = delete;
        StateLockGuard &operator=(const StateLockGuard &) = delete;
        StateLockGuard(StateLockGuard &&) = delete;
        StateLockGuard &operator=(StateLockGuard &&) = delete;

    private:
        dd_memory_live_set &table;
    };

    // Callers bound indices by kCapacity using loop limits or the bucket mask.
    std::atomic<uintptr_t> &address_at(size_t index) {
        return *(addresses + index);
    }

    void note_probe(size_t length) {
        probe_count.fetch_add(1, std::memory_order_relaxed);
        total_probe_length.fetch_add(length, std::memory_order_relaxed);
        update_peak(max_probe_length, length);
    }

    bool accepts(uint64_t token) const {
        return active.load(std::memory_order_acquire) &&
               generation.load(std::memory_order_acquire) == token;
    }
};

dd_memory_live_set_t *dd_memory_live_set::create() {
    void *storage = mmap(nullptr, sizeof(dd_memory_live_set_t),
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (storage == MAP_FAILED) {
        return nullptr;
    }

    void *slot_storage = mmap(nullptr, sizeof(Slot) * kCapacity,
                              PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (slot_storage == MAP_FAILED) {
        munmap(storage, sizeof(dd_memory_live_set_t));
        return nullptr;
    }

    auto *table = new (storage) dd_memory_live_set_t();
    table->slots = static_cast<Slot *>(slot_storage);
    for (size_t i = 0; i < kCapacity; ++i) {
        new (&table->slots[i]) Slot();
    }
    return table;
}

void dd_memory_live_set::destroy() {
    stop();
    void *table_storage = this;
    Slot *slot_storage = slots;
    for (size_t i = 0; i < kCapacity; ++i) {
        slot_storage[i].~Slot();
    }
    this->~dd_memory_live_set();
    munmap(slot_storage, sizeof(Slot) * kCapacity);
    munmap(table_storage, sizeof(dd_memory_live_set_t));
}

uint64_t dd_memory_live_set::start() {
    StateLockGuard lock(*this);
    active.store(false, std::memory_order_release);
    uint64_t token = generation.fetch_add(1, std::memory_order_acq_rel) + 1;
    if (token == 0) {
        token = generation.fetch_add(1, std::memory_order_acq_rel) + 1;
    }
    for (size_t i = 0; i < kCapacity; ++i) {
        address_at(i).store(kEmpty, std::memory_order_release);
        slots[i].sample = {};
    }
    occupancy.store(0, std::memory_order_relaxed);
    peak_occupancy.store(0, std::memory_order_relaxed);
    tombstones.store(0, std::memory_order_relaxed);
    peak_tombstones.store(0, std::memory_order_relaxed);
    dropped_samples.store(0, std::memory_order_relaxed);
    duplicate_samples.store(0, std::memory_order_relaxed);
    omitted_class_names.store(0, std::memory_order_relaxed);
    stale_generation_rejections.store(0, std::memory_order_relaxed);
    snapshot_failures.store(0, std::memory_order_relaxed);
    probe_count.store(0, std::memory_order_relaxed);
    total_probe_length.store(0, std::memory_order_relaxed);
    max_probe_length.store(0, std::memory_order_relaxed);
    snapshot_bytes_high_water.store(0, std::memory_order_relaxed);
    reached_admission_limit.store(false, std::memory_order_relaxed);
    generation_transitions.fetch_add(1, std::memory_order_relaxed);
    active.store(true, std::memory_order_release);
    return token;
}

void dd_memory_live_set::stop() {
    StateLockGuard lock(*this);
    if (active.exchange(false, std::memory_order_acq_rel)) {
        generation.fetch_add(1, std::memory_order_acq_rel);
        generation_transitions.fetch_add(1, std::memory_order_relaxed);
    }
    // Mutations and snapshots are serialized by state_lock. A miss-only
    // removal may still be traversing; hook callbacks must be drained before
    // the caller destroys the table.
}

dd_memory_live_insert_result_t dd_memory_live_set::insert(
    uint64_t token, const dd_memory_live_sample_t *sample) {
    if (sample == nullptr ||
        reinterpret_cast<uintptr_t>(sample->address) <= kTombstone ||
        sample->frame_count > DD_MEMORY_LIVE_SET_MAX_FRAMES ||
        (sample->swift_metadata == nullptr) !=
            (sample->swift_name_resolver == nullptr) ||
        (sample->class_name != nullptr && sample->swift_metadata != nullptr)) {
        return DD_MEMORY_LIVE_SET_INVALID_SAMPLE;
    }

    StateLockGuard lock(*this);
    if (!accepts(token)) {
        stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
        return DD_MEMORY_LIVE_SET_STALE_GENERATION;
    }

    const uintptr_t address = reinterpret_cast<uintptr_t>(sample->address);
    const size_t start = bucket_for(address);
    size_t available = kCapacity;
    size_t length = 0;
    for (size_t offset = 0; offset < kMaxProbe; ++offset) {
        ++length;
        const size_t index = (start + offset) & (kCapacity - 1);
        const uintptr_t current =
            address_at(index).load(std::memory_order_acquire);
        if (current == address) {
            note_probe(length);
            duplicate_samples.fetch_add(1, std::memory_order_relaxed);
            return DD_MEMORY_LIVE_SET_DUPLICATE;
        }
        if (current == kTombstone && available == kCapacity) {
            available = index;
        }
        if (current == kEmpty) {
            if (available == kCapacity) {
                available = index;
            }
            break;
        }
    }
    note_probe(length);
    if (available == kCapacity) {
        dropped_samples.fetch_add(1, std::memory_order_relaxed);
        reached_admission_limit.store(true, std::memory_order_relaxed);
        return DD_MEMORY_LIVE_SET_DROPPED;
    }

    Slot &slot = slots[available];
    const bool reused_tombstone =
        address_at(available).load(std::memory_order_relaxed) == kTombstone;
    slot.sample = *sample;
    if (sample->class_name != nullptr) {
        const size_t length = strnlen(sample->class_name, kMaxClassNameBytes);
        if (length == kMaxClassNameBytes) {
            slot.sample.class_name = nullptr;
            omitted_class_names.fetch_add(1, std::memory_order_relaxed);
        } else {
            std::memcpy(slot.class_name_storage, sample->class_name, length + 1);
            slot.sample.class_name = slot.class_name_storage;
        }
    }
    const uint64_t new_occupancy =
        occupancy.fetch_add(1, std::memory_order_relaxed) + 1;
    update_peak(peak_occupancy, new_occupancy);
    if (reused_tombstone) {
        tombstones.fetch_sub(1, std::memory_order_relaxed);
    }
    address_at(available).store(address, std::memory_order_release);
    return DD_MEMORY_LIVE_SET_INSERTED;
}

template <bool record_probe_length>
bool dd_memory_live_set::remove(uint64_t token, const void *pointer,
                                size_t *probe_length) {
    if constexpr (record_probe_length) {
        if (probe_length != nullptr) {
            *probe_length = 0;
        }
    }
    const uintptr_t address = reinterpret_cast<uintptr_t>(pointer);
    if (address <= kTombstone) {
        return false;
    }
    if (!accepts(token)) {
        stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
        return false;
    }

    const size_t start = bucket_for(address);
    for (size_t offset = 0; offset < kMaxProbe; ++offset) {
        const size_t index = (start + offset) & (kCapacity - 1);
        if constexpr (record_probe_length) {
            if (probe_length != nullptr) {
                *probe_length = offset + 1;
            }
        }
        // The probe reads only the atomic index. Hits recheck lifecycle and
        // address under state_lock before changing the table.
        const uintptr_t current = address_at(index).load(std::memory_order_relaxed);
        if (current == kEmpty) {
            return false;
        }
        if (current == address) {
            StateLockGuard lock(*this);
            if (!accepts(token)) {
                stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
                return false;
            }
            if (address_at(index).load(std::memory_order_relaxed) == address) {
                address_at(index).store(kTombstone, std::memory_order_release);
                occupancy.fetch_sub(1, std::memory_order_relaxed);
                const uint64_t new_tombstones =
                    tombstones.fetch_add(1, std::memory_order_relaxed) + 1;
                update_peak(peak_tombstones, new_tombstones);
                return true;
            }
        }
    }
    return false;
}

bool dd_memory_live_set::snapshot(
    uint64_t token, dd_memory_live_snapshot_t *snapshot) {
    const auto fail = [this] {
        snapshot_failures.fetch_add(1, std::memory_order_relaxed);
        return false;
    };
    if (snapshot == nullptr) {
        return fail();
    }
    snapshot->clear();
    StateLockGuard lock(*this);
    if (!accepts(token)) {
        stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
        return fail();
    }
    const size_t live_count =
        static_cast<size_t>(occupancy.load(std::memory_order_relaxed));
    if (live_count > kCapacity) {
        return fail();
    }

    size_t written = 0;
    size_t name_offset = 0;
    for (size_t i = 0; i < kCapacity; ++i) {
        if (address_at(i).load(std::memory_order_relaxed) <= kTombstone) {
            continue;
        }
        if (written >= live_count) {
            return fail();
        }
        size_t length = 0;
        if (!slots[i].class_name_bytes(length) ||
            name_offset > kMaxSnapshotNameBytes ||
            length > kMaxSnapshotNameBytes - name_offset) {
            return fail();
        }
        dd_memory_live_sample_t &output = snapshot->sample_at(written);
        output = slots[i].sample;
        if (length != 0) {
            std::memcpy(snapshot->storage->class_names + name_offset,
                        slots[i].sample.class_name, length);
            output.class_name = snapshot->storage->class_names + name_offset;
            name_offset += length;
        }
        ++written;
    }
    if (written != live_count) {
        return fail();
    }
    snapshot->count = written;
    update_peak(snapshot_bytes_high_water, snapshot->storage_bytes);
    return true;
}

void dd_memory_live_set::override_occupancy_for_testing(uint64_t value) {
    StateLockGuard lock(*this);
    occupancy.store(value, std::memory_order_relaxed);
}

dd_memory_live_set_diagnostics_t dd_memory_live_set::diagnostics() const {
    dd_memory_live_set_diagnostics_t result{};
    result.generation = generation.load(std::memory_order_acquire);
    result.generation_transitions =
        generation_transitions.load(std::memory_order_relaxed);
    result.occupancy = occupancy.load(std::memory_order_relaxed);
    result.peak_occupancy = peak_occupancy.load(std::memory_order_relaxed);
    result.tombstones = tombstones.load(std::memory_order_relaxed);
    result.peak_tombstones = peak_tombstones.load(std::memory_order_relaxed);
    result.dropped_samples = dropped_samples.load(std::memory_order_relaxed);
    result.duplicate_samples = duplicate_samples.load(std::memory_order_relaxed);
    result.omitted_class_names = omitted_class_names.load(std::memory_order_relaxed);
    result.stale_generation_rejections =
        stale_generation_rejections.load(std::memory_order_relaxed);
    result.snapshot_failures = snapshot_failures.load(std::memory_order_relaxed);
    result.probe_count = probe_count.load(std::memory_order_relaxed);
    result.total_probe_length =
        total_probe_length.load(std::memory_order_relaxed);
    result.max_probe_length = max_probe_length.load(std::memory_order_relaxed);
    result.table_bytes = mapped_bytes(sizeof(dd_memory_live_set_t)) +
                         mapped_bytes(sizeof(Slot) * kCapacity);
    result.snapshot_bytes_high_water =
        snapshot_bytes_high_water.load(std::memory_order_relaxed);
    result.reached_admission_limit =
        reached_admission_limit.load(std::memory_order_relaxed);
    result.is_active = active.load(std::memory_order_acquire);
    return result;
}

extern "C" dd_memory_live_snapshot_t *dd_memory_live_snapshot_create(void) {
    return dd_memory_live_snapshot::create();
}

extern "C" void dd_memory_live_snapshot_destroy(dd_memory_live_snapshot_t *snapshot) {
    if (snapshot != nullptr) {
        snapshot->destroy();
    }
}

extern "C" dd_memory_live_snapshot_view_t dd_memory_live_snapshot_view(
    const dd_memory_live_snapshot_t *snapshot) {
    return snapshot != nullptr ? snapshot->view()
                               : dd_memory_live_snapshot_view_t{};
}

extern "C" dd_memory_live_set_t *dd_memory_live_set_create(void) {
    return dd_memory_live_set::create();
}

extern "C" void dd_memory_live_set_destroy(dd_memory_live_set_t *table) {
    if (table != nullptr) {
        table->destroy();
    }
}

extern "C" uint64_t dd_memory_live_set_start(dd_memory_live_set_t *table) {
    return table != nullptr ? table->start() : 0;
}

extern "C" void dd_memory_live_set_stop(dd_memory_live_set_t *table) {
    if (table != nullptr) {
        table->stop();
    }
}

extern "C" dd_memory_live_insert_result_t dd_memory_live_set_insert(
    dd_memory_live_set_t *table, uint64_t generation,
    const dd_memory_live_sample_t *sample) {
    return table != nullptr ? table->insert(generation, sample)
                            : DD_MEMORY_LIVE_SET_INVALID_SAMPLE;
}

extern "C" bool dd_memory_live_set_remove(dd_memory_live_set_t *table,
                                          uint64_t generation, const void *address) {
    return table != nullptr && table->remove(generation, address);
}

extern "C" bool dd_memory_live_set_snapshot(
    dd_memory_live_set_t *table, uint64_t generation,
    dd_memory_live_snapshot_t *snapshot) {
    if (table == nullptr) {
        if (snapshot != nullptr) {
            snapshot->clear();
        }
        return false;
    }
    return table->snapshot(generation, snapshot);
}

extern "C" dd_memory_live_set_diagnostics_t
dd_memory_live_set_diagnostics(const dd_memory_live_set_t *table) {
    return table != nullptr ? table->diagnostics()
                            : dd_memory_live_set_diagnostics_t{};
}

extern "C" dd_memory_live_class_name_t dd_memory_live_sample_class_name(
    const dd_memory_live_sample_t *sample) {
    if (sample == nullptr) {
        return {};
    }
    if (sample->swift_metadata != nullptr && sample->swift_name_resolver != nullptr) {
        const dd_swift_class_name_t name =
            sample->swift_name_resolver(sample->swift_metadata);
        return {name.data, name.length};
    }
    if (sample->class_name != nullptr) {
        return {sample->class_name, std::strlen(sample->class_name)};
    }
    return {};
}

extern "C" size_t dd_memory_live_set_bucket(const void *address) {
    return bucket_for(reinterpret_cast<uintptr_t>(address));
}

extern "C" bool dd_memory_live_set_remove_with_probe_length_for_testing(
    dd_memory_live_set_t *table, uint64_t generation, const void *address,
    size_t *probe_length) {
    if (table == nullptr) {
        if (probe_length != nullptr) {
            *probe_length = 0;
        }
        return false;
    }
    // The production specialization compiles out probe measurement entirely.
    return table->remove<true>(generation, address, probe_length);
}

extern "C" void dd_memory_live_set_override_occupancy_for_testing(
    dd_memory_live_set_t *table, uint64_t value) {
    if (table != nullptr) {
        table->override_occupancy_for_testing(value);
    }
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
