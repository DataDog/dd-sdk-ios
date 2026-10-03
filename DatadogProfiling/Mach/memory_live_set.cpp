/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_live_set.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <atomic>
#include <cstring>
#include <new>
#include <os/lock.h>
#include <sys/mman.h>
#include <unistd.h>

namespace {

constexpr size_t kCapacity = DD_MEMORY_LIVE_SET_CAPACITY;
constexpr size_t kMaxProbe = DD_MEMORY_LIVE_SET_MAX_PROBE;
constexpr uintptr_t kEmpty = 0;
constexpr uintptr_t kTombstone = 1;
static_assert((kCapacity & (kCapacity - 1)) == 0, "capacity must be a power of two");
static_assert(kMaxProbe <= kCapacity, "probe bound must fit in the table");

struct Slot {
    os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    std::atomic<uintptr_t> address{0};
    dd_memory_live_sample_t sample{};
    char class_name_storage[DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES]{};
};

void update_peak(std::atomic<uint64_t> &peak, uint64_t value) {
    uint64_t current = peak.load(std::memory_order_relaxed);
    while (current < value &&
           !peak.compare_exchange_weak(current, value, std::memory_order_relaxed)) {}
}

size_t bucket_for(uintptr_t address) {
    uint64_t value = static_cast<uint64_t>(address >> 4);
    value ^= value >> 30;
    value *= 0xbf58476d1ce4e5b9ULL;
    value ^= value >> 27;
    value *= 0x94d049bb133111ebULL;
    value ^= value >> 31;
    return static_cast<size_t>(value) & (kCapacity - 1);
}

size_t mapped_bytes(size_t bytes) {
    const size_t page_size = static_cast<size_t>(getpagesize());
    return ((bytes + page_size - 1) / page_size) * page_size;
}

} // namespace

struct dd_memory_live_set {
    static dd_memory_live_set_t *create();
    void destroy();
    uint64_t start();
    void stop();
    dd_memory_live_insert_result_t insert(uint64_t token,
                                          const dd_memory_live_sample_t *sample);
    bool remove(uint64_t token, const void *pointer);
    bool snapshot(uint64_t token, dd_memory_live_sample_t *output,
                  size_t output_capacity, char *class_names,
                  size_t class_names_capacity, size_t *count,
                  size_t *class_name_bytes_required);
    dd_memory_live_set_diagnostics_t diagnostics() const;

private:
    os_unfair_lock insertion_lock = OS_UNFAIR_LOCK_INIT;
    Slot *slots = nullptr;
    std::atomic<bool> active{false};
    std::atomic<uint64_t> generation{0};
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

    void lock_all_slots() {
        for (size_t i = 0; i < kCapacity; ++i) {
            os_unfair_lock_lock(&slots[i].lock);
        }
    }

    void unlock_all_slots() {
        for (size_t i = kCapacity; i > 0; --i) {
            os_unfair_lock_unlock(&slots[i - 1].lock);
        }
    }

    class SnapshotLockGuard {
    public:
        explicit SnapshotLockGuard(dd_memory_live_set &table) : table(table) {
            os_unfair_lock_lock(&table.insertion_lock);
            table.lock_all_slots();
        }

        ~SnapshotLockGuard() {
            table.unlock_all_slots();
            os_unfair_lock_unlock(&table.insertion_lock);
        }

        SnapshotLockGuard(const SnapshotLockGuard &) = delete;
        SnapshotLockGuard &operator=(const SnapshotLockGuard &) = delete;

    private:
        dd_memory_live_set &table;
    };

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
    os_unfair_lock_lock(&insertion_lock);
    active.store(false, std::memory_order_release);
    uint64_t token = generation.fetch_add(1, std::memory_order_acq_rel) + 1;
    if (token == 0) {
        token = generation.fetch_add(1, std::memory_order_acq_rel) + 1;
    }
    lock_all_slots();
    for (size_t i = 0; i < kCapacity; ++i) {
        slots[i].address.store(kEmpty, std::memory_order_release);
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
    unlock_all_slots();
    os_unfair_lock_unlock(&insertion_lock);
    return token;
}

void dd_memory_live_set::stop() {
    os_unfair_lock_lock(&insertion_lock);
    if (active.exchange(false, std::memory_order_acq_rel)) {
        generation.fetch_add(1, std::memory_order_acq_rel);
        generation_transitions.fetch_add(1, std::memory_order_relaxed);
    }
    // Inserts and snapshots are serialized by insertion_lock. A miss-only
    // removal may still be traversing; hook callbacks must be drained before
    // the caller destroys the table.
    lock_all_slots();
    unlock_all_slots();
    os_unfair_lock_unlock(&insertion_lock);
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

    os_unfair_lock_lock(&insertion_lock);
    if (!accepts(token)) {
        stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
        os_unfair_lock_unlock(&insertion_lock);
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
            slots[index].address.load(std::memory_order_acquire);
        if (current == address) {
            note_probe(length);
            duplicate_samples.fetch_add(1, std::memory_order_relaxed);
            os_unfair_lock_unlock(&insertion_lock);
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
        os_unfair_lock_unlock(&insertion_lock);
        return DD_MEMORY_LIVE_SET_DROPPED;
    }

    Slot &slot = slots[available];
    os_unfair_lock_lock(&slot.lock);
    const bool reused_tombstone =
        slot.address.load(std::memory_order_relaxed) == kTombstone;
    slot.sample = *sample;
    if (sample->class_name != nullptr) {
        const size_t length = strnlen(sample->class_name,
                                      DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES);
        if (length == DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES) {
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
    slot.address.store(address, std::memory_order_release);
    os_unfair_lock_unlock(&slot.lock);
    os_unfair_lock_unlock(&insertion_lock);
    return DD_MEMORY_LIVE_SET_INSERTED;
}

bool dd_memory_live_set::remove(uint64_t token, const void *pointer) {
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
        Slot &slot = slots[index];
        const uintptr_t current = slot.address.load(std::memory_order_acquire);
        if (current == kEmpty) {
            return false;
        }
        if (current == address) {
            os_unfair_lock_lock(&slot.lock);
            if (!accepts(token)) {
                stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
                os_unfair_lock_unlock(&slot.lock);
                return false;
            }
            if (slot.address.load(std::memory_order_relaxed) == address) {
                slot.address.store(kTombstone, std::memory_order_release);
                occupancy.fetch_sub(1, std::memory_order_relaxed);
                const uint64_t new_tombstones =
                    tombstones.fetch_add(1, std::memory_order_relaxed) + 1;
                update_peak(peak_tombstones, new_tombstones);
                os_unfair_lock_unlock(&slot.lock);
                return true;
            }
            os_unfair_lock_unlock(&slot.lock);
        }
    }
    return false;
}

bool dd_memory_live_set::snapshot(
    uint64_t token, dd_memory_live_sample_t *output,
    size_t output_capacity, char *class_names,
    size_t class_names_capacity, size_t *count,
    size_t *class_name_bytes_required) {
    const auto fail = [this] {
        snapshot_failures.fetch_add(1, std::memory_order_relaxed);
        return false;
    };
    if (count == nullptr) {
        return fail();
    }
    *count = 0;
    if (class_name_bytes_required != nullptr) {
        *class_name_bytes_required = 0;
    }
    SnapshotLockGuard locks(*this);
    if (!accepts(token)) {
        stale_generation_rejections.fetch_add(1, std::memory_order_relaxed);
        return fail();
    }
    const size_t live_count =
        static_cast<size_t>(occupancy.load(std::memory_order_relaxed));
    if (live_count > output_capacity || (live_count != 0 && output == nullptr)) {
        return fail();
    }

    size_t names_required = 0;
    for (size_t i = 0; i < kCapacity; ++i) {
        if (slots[i].address.load(std::memory_order_relaxed) > kTombstone &&
            slots[i].sample.class_name != nullptr) {
            const size_t length = std::strlen(slots[i].sample.class_name) + 1;
            if (length == 0 || names_required > SIZE_MAX - length) {
                return fail();
            }
            names_required += length;
        }
    }
    if (class_name_bytes_required != nullptr) {
        *class_name_bytes_required = names_required;
    }
    if (names_required > class_names_capacity ||
        (names_required != 0 && class_names == nullptr)) {
        return fail();
    }

    size_t written = 0;
    size_t name_offset = 0;
    for (size_t i = 0; i < kCapacity; ++i) {
        const uintptr_t address =
            slots[i].address.load(std::memory_order_relaxed);
        if (address > kTombstone) {
            output[written++] = slots[i].sample;
            if (slots[i].sample.class_name != nullptr) {
                const size_t length = std::strlen(slots[i].sample.class_name) + 1;
                std::memcpy(class_names + name_offset,
                            slots[i].sample.class_name, length);
                output[written - 1].class_name = class_names + name_offset;
                name_offset += length;
            }
        }
    }
    *count = written;
    const uint64_t declared_bytes =
        output_capacity > (UINT64_MAX - class_names_capacity) /
                              sizeof(dd_memory_live_sample_t)
            ? UINT64_MAX
            : output_capacity * sizeof(dd_memory_live_sample_t) +
                  class_names_capacity;
    update_peak(snapshot_bytes_high_water, declared_bytes);
    return true;
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
    dd_memory_live_set_t *table, uint64_t token,
    const dd_memory_live_sample_t *sample) {
    return table != nullptr ? table->insert(token, sample)
                            : DD_MEMORY_LIVE_SET_INVALID_SAMPLE;
}

extern "C" bool dd_memory_live_set_remove(dd_memory_live_set_t *table,
                                          uint64_t token, const void *pointer) {
    return table != nullptr && table->remove(token, pointer);
}

extern "C" bool dd_memory_live_set_snapshot(
    dd_memory_live_set_t *table, uint64_t token, dd_memory_live_sample_t *output,
    size_t output_capacity, char *class_names, size_t class_names_capacity,
    size_t *count, size_t *class_name_bytes_required) {
    if (table == nullptr) {
        if (count != nullptr) {
            *count = 0;
        }
        if (class_name_bytes_required != nullptr) {
            *class_name_bytes_required = 0;
        }
        return false;
    }
    return table->snapshot(token, output, output_capacity, class_names,
                           class_names_capacity, count,
                           class_name_bytes_required);
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

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
