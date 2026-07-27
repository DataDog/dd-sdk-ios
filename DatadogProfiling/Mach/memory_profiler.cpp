/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_profiler.h"
#include "memory_profiler_testing.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <execinfo.h>
#include <mach/mach.h>
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <mach/vm_map.h>
#include <mach/vm_page_size.h>
#include <malloc/malloc.h>
#include <limits>
#include <new>
#include <os/lock.h>
#include <pthread.h>
#include <random>
#include <sys/mman.h>

// =====================================================================
// Memory Profiler RFC reference implementation (RUM-16460)
//
// The implementation validates the RFC's risky technical assumptions:
//
//   1. Can we install malloc_zone_t hooks in an App Store release build?
//   2. What is the actual overhead of Poisson sampling at B=512 KB?
//   3. Does the collocated is_sampled bitmap work on iOS, or do we need
//      a separate tracking structure?
//   4. Is vm_region_recurse_64 reliable for VM decomposition?
//
// Question 4 is answered by vm_region_walker.cpp. The rest live here.
//
// Implementation overview:
//   - install_hooks() probes whether the default zone struct is writable
//     and reports back which path was taken.
//   - Each hook funnels through hook_post_alloc()/hook_pre_free() which
//     check a global enabled flag and per-thread reentrancy guard before
//     doing any work.
//   - Poisson sampling is per-thread: each thread keeps a byte counter
//     and decrements on every allocation. When the counter falls to
//     zero, the allocation is sampled and a new threshold drawn from
//     exp(B).
//   - Sampled allocations are stored in a fixed-size, pre-allocated
//     hash table. Slot metadata is synchronized and snapshot-consistent;
//     we never call malloc from inside a hook (would recurse) or grow
//     the table at runtime.
//
// Q3 conclusion (see findings doc in Simao's Brain wiki):
// collocating a bit alongside libmalloc's per-slot `in_use` bitmap is
// NOT App Store safe because libmalloc internals are private. We use
// a side hash table instead.
// =====================================================================

namespace {

// MARK: - Tunables

/// Maximum simultaneously tracked sampled allocations.
/// 4096 entries cover the live-sampled set comfortably at B=512 KB —
/// e.g. a 100 MB heap with that rate yields ~200 live samples.
/// Sized at compile time so the table can live in a pre-allocated mmap
/// region and we never grow it (growth would require malloc, which would
/// recurse into the hook).
constexpr size_t SAMPLE_TABLE_CAPACITY = 4096;
static_assert(
    (SAMPLE_TABLE_CAPACITY & (SAMPLE_TABLE_CAPACITY - 1)) == 0,
    "The sample table capacity must remain a power of two"
);

/// Maximum stack frames captured per sampled allocation. Must match the
/// public `dd_memory_sample_t::frames` array size.
constexpr uint32_t SAMPLE_STACK_DEPTH = DD_MEMORY_DEFAULT_STACK_DEPTH;

// MARK: - Internal sample entry

/// One slot in the live-sample hash table.
///
/// `addr` is the atomically-published slot state and key:
/// - 0: never occupied (terminates an unsuccessful lookup)
/// - 1: tombstone (freed, but lookups must continue past it)
/// - >1: live allocation address
///
/// Metadata is immutable while an entry is live and protected by `lock`
/// while being written, copied into a snapshot, or transitioned to a
/// tombstone. This prevents snapshots from racing with slot reuse.
struct sample_entry {
    os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    std::atomic<uint64_t> addr{0};
    uint64_t size{0};
    double weight{1.0};
    uint64_t timestamp_ns{0};
    uint64_t frames[SAMPLE_STACK_DEPTH]{};
    uint32_t frame_count{0};
    /// Class name for Obj-C/Swift instances observed via the swizzle path;
    /// nullptr for raw C/zone-hook allocations. Pointer lifetime is the
    /// caller's responsibility (Obj-C class names from class_getName are
    /// stable for the life of the class).
    const char* class_name{nullptr};
};

// MARK: - Global state

/// Original zone function pointers, captured at install time so we can
/// forward unsampled allocations and reentrant calls to the real allocator.
struct original_zone_funcs {
    void* (*malloc_fn)(malloc_zone_t*, size_t) = nullptr;
    void* (*calloc_fn)(malloc_zone_t*, size_t, size_t) = nullptr;
    void* (*valloc_fn)(malloc_zone_t*, size_t) = nullptr;
    void (*free_fn)(malloc_zone_t*, void*) = nullptr;
    void (*free_definite_size_fn)(malloc_zone_t*, void*, size_t) = nullptr;
    void* (*realloc_fn)(malloc_zone_t*, void*, size_t) = nullptr;
    void* (*memalign_fn)(malloc_zone_t*, size_t, size_t) = nullptr;
};

/// Whether the hook layer should perform any work. A successful acquire
/// load publishes the table and session configuration initialized before
/// the corresponding release store at session start.
std::atomic<bool> g_profiler_enabled{false};

/// Monotonically increasing session identity. Slow-path insertions capture
/// the current value and validate it again while holding `g_insert_lock`,
/// preventing work started in one session from entering a later session.
std::atomic<uint64_t> g_session_generation{0};

/// Pre-allocated table of live sampled allocations. Lives for the
/// lifetime of the process once installed (no destructor — we never
/// shut down cleanly because hook pointers may have been overwritten
/// by other tools after us).
sample_entry* g_samples = nullptr;

/// Mach timebase converted to nanoseconds — cached after first use.
mach_timebase_info_data_t g_timebase = {};

/// Profiler start time in mach ticks; sample timestamps are deltas
/// from this anchor.
std::atomic<uint64_t> g_start_ticks{0};

/// Function pointers we captured before installing our hooks.
original_zone_funcs g_original;

/// Poisson sampling rate (mean bytes between samples). Set at start.
std::atomic<uint64_t> g_poisson_rate_bytes{DD_MEMORY_POISSON_DEFAULT_RATE_BYTES};

// MARK: - Diagnostics

std::atomic<uint64_t> g_total_bytes_allocated{0};
std::atomic<uint64_t> g_total_allocations{0};
std::atomic<uint64_t> g_sampled_allocations{0};
std::atomic<uint64_t> g_dropped_samples{0};
std::atomic<uint64_t> g_sampled_frees{0};
std::atomic<uint64_t> g_live_sampled_allocations{0};
std::atomic<uint64_t> g_reentrant_skips{0};
std::atomic<uint64_t> g_unsampled_calls{0};

/// Sampling insertions are rare relative to observed allocations. Serializing
/// them prevents duplicate keys while per-entry locks keep free-side lookups
/// and snapshots independent.
os_unfair_lock g_insert_lock = OS_UNFAIR_LOCK_INIT;

/// Serializes start, stop, and test reset, including first-time hook and
/// sample-table installation.
os_unfair_lock g_lifecycle_lock = OS_UNFAIR_LOCK_INIT;

// MARK: - Per-thread state

/// Reentrancy guard: while a hook is doing its bookkeeping (backtrace,
/// table insert), nested malloc/free calls from that bookkeeping must
/// be passed straight through to the original allocator. Otherwise we
/// would infinitely recurse the first time backtrace() needs scratch
/// memory.
thread_local bool tls_in_profiler = false;

/// Bytes remaining until the next sample. Per-thread because contention
/// on a global counter would dominate the hot path. The counter is
/// redrawn from exp(B) after every sample.
thread_local int64_t tls_bytes_until_sample = 0;

/// Session for which the per-thread Poisson threshold was drawn. Each thread
/// receives a fresh exponential threshold when it first allocates in a new
/// session, avoiding the deterministic "first allocation is sampled" bias.
thread_local uint64_t tls_sampling_generation = 0;

/// Force the next allocation to be sampled regardless of the counter.
/// Used only by tests; production code never touches this.
thread_local bool tls_force_next_sample = false;

// MARK: - Time helpers

uint64_t ticks_to_nanos(uint64_t ticks) {
    return (ticks * g_timebase.numer) / g_timebase.denom;
}

uint64_t monotonic_ns_since_start() {
    const uint64_t start_ticks = g_start_ticks.load(std::memory_order_acquire);
    const uint64_t now_ticks = mach_absolute_time();
    return ticks_to_nanos(now_ticks >= start_ticks ? now_ticks - start_ticks : 0);
}

// MARK: - Poisson sampling

/// Draws the next sampling threshold from an exponential distribution
/// with the configured mean. This is the Poisson process the
/// Go heap profiler and heapprofd use: each byte has equal probability
/// 1/B of being sampled.
///
/// Uses a per-thread random_device since `rand()` would be a global
/// contention point — and the random_device implementation on Apple
/// platforms is backed by /dev/urandom, which is fine for our cadence.
int64_t draw_next_threshold(uint64_t poisson_rate_bytes) {
    thread_local std::mt19937_64 rng(std::random_device{}());
    thread_local std::exponential_distribution<double> dist(1.0);
    const double sample = dist(rng) * static_cast<double>(poisson_rate_bytes);
    const double maximum = static_cast<double>(std::numeric_limits<int64_t>::max() - 1);
    if (!std::isfinite(sample) || sample >= maximum) {
        return std::numeric_limits<int64_t>::max();
    }
    return static_cast<int64_t>(sample) + 1;
}

/// Returns the Poisson scaling weight for a given allocation size.
/// Each sampled allocation represents `weight` objects and `size * weight`
/// bytes of the unsampled population. The formula comes from the CDF of the
/// exponential distribution: P(sampled) = 1 - exp(-size / rate).
double poisson_weight_for_size(uint64_t size, uint64_t poisson_rate_bytes) {
    if (poisson_rate_bytes == 0) {
        return 1.0;
    }
    const double p = 1.0 - std::exp(-static_cast<double>(size) / static_cast<double>(poisson_rate_bytes));
    if (p <= 0.0) {
        return size > 0
            ? static_cast<double>(poisson_rate_bytes) / static_cast<double>(size)
            : 1.0;
    }
    return 1.0 / p;
}

// MARK: - Live-sample table

constexpr uint64_t EMPTY_SLOT = 0;
constexpr uint64_t TOMBSTONE_SLOT = 1;

bool is_live_address(uint64_t addr) {
    return addr > TOMBSTONE_SLOT;
}

/// Open-addressing hash for pointers. Discard known-zero alignment bits and
/// apply the SplitMix64 finalizer so adjacent allocator addresses distribute
/// across the power-of-two table instead of clustering in nearby buckets.
size_t bucket_for(uint64_t ptr) {
    uint64_t value = ptr >> 4;
    value ^= value >> 30;
    value *= 0xbf58476d1ce4e5b9ULL;
    value ^= value >> 27;
    value *= 0x94d049bb133111ebULL;
    value ^= value >> 31;
    return value & (SAMPLE_TABLE_CAPACITY - 1);
}

enum class insert_result {
    inserted,
    rejected_session,
    rejected_table
};

/// Inserts a sampled allocation into the live-set table. Linear probing
/// preserves the first tombstone for reuse but continues until an empty
/// slot to reject duplicate keys. Insertions are serialized because they
/// are already on the sampled slow path.
insert_result insert_sample(uint64_t addr, uint64_t size, double weight,
                            const uint64_t* frames, uint32_t frame_count,
                            const char* class_name, uint64_t session_generation) {
    if (!is_live_address(addr)) {
        return insert_result::rejected_table;
    }

    os_unfair_lock_lock(&g_insert_lock);
    if (!g_profiler_enabled.load(std::memory_order_acquire)
        || g_session_generation.load(std::memory_order_acquire) != session_generation) {
        os_unfair_lock_unlock(&g_insert_lock);
        return insert_result::rejected_session;
    }

    // Count the sampling decision only after proving that this slow-path work
    // still belongs to the active session. Lifecycle transitions hold the same
    // lock, so diagnostics cannot leak across a reset.
    g_sampled_allocations.fetch_add(1, std::memory_order_relaxed);

    size_t available_idx = SAMPLE_TABLE_CAPACITY;
    const size_t start = bucket_for(addr);

    for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
        const size_t idx = (start + i) % SAMPLE_TABLE_CAPACITY;
        const uint64_t current = g_samples[idx].addr.load(std::memory_order_acquire);

        if (current == addr) {
            g_dropped_samples.fetch_add(1, std::memory_order_relaxed);
            os_unfair_lock_unlock(&g_insert_lock);
            return insert_result::rejected_table;
        }
        if (current == TOMBSTONE_SLOT && available_idx == SAMPLE_TABLE_CAPACITY) {
            available_idx = idx;
            continue;
        }
        if (current == EMPTY_SLOT) {
            if (available_idx == SAMPLE_TABLE_CAPACITY) {
                available_idx = idx;
            }
            break;
        }
    }

    if (available_idx == SAMPLE_TABLE_CAPACITY) {
        g_dropped_samples.fetch_add(1, std::memory_order_relaxed);
        os_unfair_lock_unlock(&g_insert_lock);
        return insert_result::rejected_table;
    }

    sample_entry& entry = g_samples[available_idx];
    os_unfair_lock_lock(&entry.lock);
    entry.size = size;
    entry.weight = weight;
    entry.timestamp_ns = monotonic_ns_since_start();
    const uint32_t to_copy = (frame_count > SAMPLE_STACK_DEPTH) ? SAMPLE_STACK_DEPTH : frame_count;
    std::memset(entry.frames, 0, sizeof(entry.frames));
    if (to_copy > 0) {
        std::memcpy(entry.frames, frames, to_copy * sizeof(uint64_t));
    }
    entry.frame_count = to_copy;
    entry.class_name = class_name;

    // Count before publishing the address so a concurrent remove can never
    // observe a live key before the corresponding live count exists.
    g_live_sampled_allocations.fetch_add(1, std::memory_order_relaxed);
    entry.addr.store(addr, std::memory_order_release);
    os_unfair_lock_unlock(&entry.lock);
    os_unfair_lock_unlock(&g_insert_lock);
    return insert_result::inserted;
}

/// Finds and clears a tracked allocation. Returns true if found.
/// Used on free hook to remove the entry from the live set.
bool remove_sample(uint64_t addr, uint64_t session_generation) {
    if (!is_live_address(addr)) {
        return false;
    }

    const size_t start = bucket_for(addr);
    for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
        const size_t idx = (start + i) % SAMPLE_TABLE_CAPACITY;
        sample_entry& entry = g_samples[idx];
        const uint64_t current = entry.addr.load(std::memory_order_acquire);
        if (current == EMPTY_SLOT) {
            // We've probed past the cluster; the addr wasn't in our set.
            // This is the common case for unsampled frees.
            return false;
        }
        if (current == addr) {
            os_unfair_lock_lock(&entry.lock);
            if (g_profiler_enabled.load(std::memory_order_acquire)
                && g_session_generation.load(std::memory_order_acquire) == session_generation
                && entry.addr.load(std::memory_order_relaxed) == addr) {
                // A tombstone preserves the probe chain for colliding keys.
                entry.addr.store(TOMBSTONE_SLOT, std::memory_order_release);
                g_live_sampled_allocations.fetch_sub(1, std::memory_order_relaxed);
                g_sampled_frees.fetch_add(1, std::memory_order_relaxed);
                os_unfair_lock_unlock(&entry.lock);
                return true;
            }
            os_unfair_lock_unlock(&entry.lock);
        }
    }
    return false;
}

void lock_all_sample_entries() {
    for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
        os_unfair_lock_lock(&g_samples[i].lock);
    }
}

void unlock_all_sample_entries() {
    for (size_t i = SAMPLE_TABLE_CAPACITY; i > 0; --i) {
        os_unfair_lock_unlock(&g_samples[i - 1].lock);
    }
}

void clear_sample_table_locked() {
    if (g_samples == nullptr) {
        return;
    }

    for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
        sample_entry& entry = g_samples[i];
        os_unfair_lock_lock(&entry.lock);
        entry.addr.store(EMPTY_SLOT, std::memory_order_release);
        entry.size = 0;
        entry.weight = 1.0;
        entry.timestamp_ns = 0;
        std::memset(entry.frames, 0, sizeof(entry.frames));
        entry.frame_count = 0;
        entry.class_name = nullptr;
        os_unfair_lock_unlock(&entry.lock);
    }
    g_live_sampled_allocations.store(0, std::memory_order_release);
}

// MARK: - Backtrace capture

/// Captures a stack trace for the current thread. The first two frames
/// are typically (our hook, the malloc shim) — caller can skip those
/// at presentation time.
uint32_t capture_backtrace(uint64_t* frames, uint32_t max_frames) {
    void* buffer[SAMPLE_STACK_DEPTH];
    const int count = backtrace(buffer, static_cast<int>(max_frames));
    if (count <= 0) {
        return 0;
    }
    const uint32_t valid = static_cast<uint32_t>(count);
    for (uint32_t i = 0; i < valid; ++i) {
        frames[i] = reinterpret_cast<uint64_t>(buffer[i]);
    }
    return valid;
}

// MARK: - Hook entry points

/// Per-allocation bookkeeping invoked after the original allocator
/// returns a pointer. Handles diagnostic counters, the Poisson decision,
/// and (when sampled) the table insertion. Returns the input pointer
/// unchanged so hook wrappers can `return record_allocation(...)`.
/// @param class_name Optional Obj-C/Swift class name (from class_getName);
///                   stored verbatim in the sample. nullptr for zone-hook path.
void* record_allocation(void* ptr, size_t size, const char* class_name = nullptr) {
    if (ptr == nullptr) {
        return ptr;
    }

    // The acquire pairs with session start, publishing the table, sampling
    // configuration, and generation before this hook observes them.
    if (!g_profiler_enabled.load(std::memory_order_acquire)) {
        return ptr;
    }
    const uint64_t session_generation = g_session_generation.load(std::memory_order_acquire);
    const uint64_t poisson_rate_bytes = g_poisson_rate_bytes.load(std::memory_order_acquire);

    g_total_allocations.fetch_add(1, std::memory_order_relaxed);
    g_total_bytes_allocated.fetch_add(size, std::memory_order_relaxed);

    // Reentrancy guard: backtrace() and Mach calls can themselves
    // allocate, and would recurse into this hook. We never re-enter.
    if (tls_in_profiler) {
        g_reentrant_skips.fetch_add(1, std::memory_order_relaxed);
        return ptr;
    }

    if (tls_sampling_generation != session_generation) {
        tls_sampling_generation = session_generation;
        tls_bytes_until_sample = draw_next_threshold(poisson_rate_bytes);
        tls_force_next_sample = false;
    }

    // Poisson decision: decrement and check. If we cross zero (or the
    // test override forces us), sample this allocation.
    bool should_sample = tls_force_next_sample;
    if (!should_sample) {
        should_sample = tls_bytes_until_sample <= 0
            || size >= static_cast<uint64_t>(tls_bytes_until_sample);
        if (!should_sample) {
            tls_bytes_until_sample -= static_cast<int64_t>(size);
        }
    }
    if (!should_sample) {
        g_unsampled_calls.fetch_add(1, std::memory_order_relaxed);
        return ptr;
    }
    tls_force_next_sample = false;
    tls_bytes_until_sample = draw_next_threshold(poisson_rate_bytes);

    // Enter the sampling slow path. Any allocation made by backtrace()
    // or the table machinery from here on must short-circuit via the
    // tls_in_profiler check above.
    tls_in_profiler = true;
    uint64_t frames[SAMPLE_STACK_DEPTH];
    const uint32_t frame_count = capture_backtrace(frames, SAMPLE_STACK_DEPTH);
    const double weight = poisson_weight_for_size(size, poisson_rate_bytes);
    insert_sample(
        reinterpret_cast<uint64_t>(ptr),
        size,
        weight,
        frames,
        frame_count,
        class_name,
        session_generation
    );
    tls_in_profiler = false;
    return ptr;
}

/// Per-free bookkeeping. Removes the entry from the live set if we
/// were tracking it. Unsampled frees fall straight through, costing
/// only the probe-then-stop path in `remove_sample` (one or two
/// cache-line reads).
void record_free(void* ptr) {
    if (ptr == nullptr) {
        return;
    }
    if (!g_profiler_enabled.load(std::memory_order_acquire)) {
        return;
    }
    const uint64_t session_generation = g_session_generation.load(std::memory_order_acquire);
    if (tls_in_profiler) {
        return;
    }
    remove_sample(reinterpret_cast<uint64_t>(ptr), session_generation);
}

// MARK: - Hook implementations
//
// Each hook delegates to the original function pointer captured at
// install time, then runs our bookkeeping. We never replace the
// allocator behavior — only observe it.

void* hooked_malloc(malloc_zone_t* zone, size_t size) {
    void* ptr = g_original.malloc_fn(zone, size);
    return record_allocation(ptr, size);
}

void* hooked_calloc(malloc_zone_t* zone, size_t num_items, size_t item_size) {
    void* ptr = g_original.calloc_fn(zone, num_items, item_size);
    return record_allocation(ptr, num_items * item_size);
}

void* hooked_valloc(malloc_zone_t* zone, size_t size) {
    void* ptr = g_original.valloc_fn(zone, size);
    return record_allocation(ptr, size);
}

void hooked_free(malloc_zone_t* zone, void* ptr) {
    record_free(ptr);
    g_original.free_fn(zone, ptr);
}

void hooked_free_definite_size(malloc_zone_t* zone, void* ptr, size_t size) {
    record_free(ptr);
    g_original.free_definite_size_fn(zone, ptr, size);
}

void* hooked_realloc(malloc_zone_t* zone, void* ptr, size_t size) {
    // Treat realloc as a free + alloc pair for tracking purposes.
    // This loses the connection between original and reallocated
    // pointers, but covers the common case where the allocator moves
    // the region. The in-place case (same pointer back) leaks a stale
    // size in the tracked entry — documented gap.
    record_free(ptr);
    void* new_ptr = g_original.realloc_fn(zone, ptr, size);
    return record_allocation(new_ptr, size);
}

void* hooked_memalign(malloc_zone_t* zone, size_t alignment, size_t size) {
    if (g_original.memalign_fn == nullptr) {
        return nullptr;
    }
    void* ptr = g_original.memalign_fn(zone, alignment, size);
    return record_allocation(ptr, size);
}

// MARK: - Installation

/// Probes whether the default zone struct lives on a writable page.
/// Reads the current malloc field, attempts to write the same value
/// back, and checks whether the write took. If the page is read-only,
/// the write segfaults via the kernel's protection check and we never
/// reach here — so we use vm_region_recurse_64 to inspect protection
/// up front and avoid the crash.
bool probe_zone_writable(malloc_zone_t* zone) {
    if (zone == nullptr) {
        return false;
    }
    vm_address_t addr = reinterpret_cast<vm_address_t>(zone);
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info = {};
    mach_msg_type_number_t info_count = VM_REGION_SUBMAP_INFO_COUNT_64;
    const kern_return_t kr = vm_region_recurse_64(mach_task_self(),
                                                    &addr, &size, &depth,
                                                    reinterpret_cast<vm_region_recurse_info_t>(&info),
                                                    &info_count);
    if (kr != KERN_SUCCESS) {
        return false;
    }
    // Protection field is a bitmask of VM_PROT_READ / VM_PROT_WRITE /
    // VM_PROT_EXECUTE. We need WRITE permission to install hooks
    // without mprotect.
    return (info.protection & VM_PROT_WRITE) != 0;
}

/// Attempts to make the default zone struct's page writable using
/// mprotect. The page is restored to its original protection after
/// hooks are installed.
bool make_zone_writable(malloc_zone_t* zone, vm_prot_t* original_prot_out) {
    vm_address_t addr = reinterpret_cast<vm_address_t>(zone);
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info = {};
    mach_msg_type_number_t info_count = VM_REGION_SUBMAP_INFO_COUNT_64;
    const kern_return_t region_kr = vm_region_recurse_64(mach_task_self(),
                                                            &addr, &size, &depth,
                                                            reinterpret_cast<vm_region_recurse_info_t>(&info),
                                                            &info_count);
    if (region_kr != KERN_SUCCESS) {
        return false;
    }
    *original_prot_out = info.protection;

    void* page_start = reinterpret_cast<void*>(addr);
    const size_t page_size = static_cast<size_t>(vm_kernel_page_size);
    if (mprotect(page_start, page_size, PROT_READ | PROT_WRITE) != 0) {
        return false;
    }
    return true;
}

void restore_zone_protection(malloc_zone_t* zone, vm_prot_t original_prot) {
    vm_address_t addr = reinterpret_cast<vm_address_t>(zone);
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info = {};
    mach_msg_type_number_t info_count = VM_REGION_SUBMAP_INFO_COUNT_64;
    vm_region_recurse_64(mach_task_self(), &addr, &size, &depth,
                           reinterpret_cast<vm_region_recurse_info_t>(&info),
                           &info_count);

    void* page_start = reinterpret_cast<void*>(addr);
    const size_t page_size = static_cast<size_t>(vm_kernel_page_size);
    int prot_flags = 0;
    if ((original_prot & VM_PROT_READ) != 0) prot_flags |= PROT_READ;
    if ((original_prot & VM_PROT_WRITE) != 0) prot_flags |= PROT_WRITE;
    if ((original_prot & VM_PROT_EXECUTE) != 0) prot_flags |= PROT_EXEC;
    if (prot_flags == 0) {
        prot_flags = PROT_READ;
    }
    mprotect(page_start, page_size, prot_flags);
}

void capture_originals(malloc_zone_t* zone) {
    g_original.malloc_fn = zone->malloc;
    g_original.calloc_fn = zone->calloc;
    g_original.valloc_fn = zone->valloc;
    g_original.free_fn = zone->free;
    g_original.free_definite_size_fn = zone->free_definite_size;
    g_original.realloc_fn = zone->realloc;
    g_original.memalign_fn = zone->memalign;
}

/// Detects whether another tool has already replaced the zone's hooks
/// (e.g. Bugsnag, Sentry, MallocStackLogging, or a sanitizer). If the
/// function pointers don't point inside the libsystem image, we assume
/// someone else got there first and refuse to install. We can chain
/// in the future but that's beyond the POC scope.
bool zone_has_default_hooks(malloc_zone_t* zone) {
    if (zone == nullptr || zone->malloc == nullptr) {
        return false;
    }
    // Sentinel addresses from libsystem are in the dyld shared cache,
    // typically high in user space. The simplest detection is whether
    // the pointer matches any other zone we'd return to — but that
    // adds complexity. For the POC, we just check that the pointer
    // is not one of OUR hooks (paranoia for repeated installs).
    return zone->malloc != hooked_malloc;
}

bool ensure_sample_table_allocated() {
    if (g_samples != nullptr) {
        return true;
    }
    // mmap'd anonymous memory is independent of the malloc allocator.
    // Using malloc here would either fail (hooks not yet installed
    // so it's safe right now) or, more dangerously, be tracked once
    // hooks turn on. mmap avoids the question entirely.
    const size_t bytes = sizeof(sample_entry) * SAMPLE_TABLE_CAPACITY;
    void* mem = mmap(nullptr, bytes, PROT_READ | PROT_WRITE,
                     MAP_ANON | MAP_PRIVATE, -1, 0);
    if (mem == MAP_FAILED) {
        return false;
    }
    g_samples = static_cast<sample_entry*>(mem);
    // mmap provides storage, but C++ object lifetime still begins through
    // placement construction so atomics and per-entry locks are initialized.
    for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
        new (&g_samples[i]) sample_entry();
    }
    return true;
}

void reset_diagnostics() {
    g_total_bytes_allocated.store(0, std::memory_order_relaxed);
    g_total_allocations.store(0, std::memory_order_relaxed);
    g_sampled_allocations.store(0, std::memory_order_relaxed);
    g_dropped_samples.store(0, std::memory_order_relaxed);
    g_sampled_frees.store(0, std::memory_order_relaxed);
    g_reentrant_skips.store(0, std::memory_order_relaxed);
    g_unsampled_calls.store(0, std::memory_order_relaxed);
}

void start_new_session(uint64_t poisson_rate_bytes) {
    const uint64_t normalized_rate = poisson_rate_bytes > 0
        ? poisson_rate_bytes
        : DD_MEMORY_POISSON_DEFAULT_RATE_BYTES;

    os_unfair_lock_lock(&g_insert_lock);
    g_profiler_enabled.store(false, std::memory_order_release);
    g_session_generation.fetch_add(1, std::memory_order_acq_rel);
    g_poisson_rate_bytes.store(normalized_rate, std::memory_order_release);
    g_start_ticks.store(mach_absolute_time(), std::memory_order_release);
    clear_sample_table_locked();
    reset_diagnostics();
    g_profiler_enabled.store(true, std::memory_order_release);
    os_unfair_lock_unlock(&g_insert_lock);
}

void stop_current_session() {
    os_unfair_lock_lock(&g_insert_lock);
    if (!g_profiler_enabled.exchange(false, std::memory_order_acq_rel)) {
        os_unfair_lock_unlock(&g_insert_lock);
        return;
    }

    g_session_generation.fetch_add(1, std::memory_order_acq_rel);

    // An old free-side operation can already own an entry lock. Acquiring all
    // locks after invalidating the generation drains those operations before
    // stop returns, while future operations observe the disabled flag.
    lock_all_sample_entries();
    unlock_all_sample_entries();
    os_unfair_lock_unlock(&g_insert_lock);
}

} // namespace

// MARK: - Public API

extern "C" dd_memory_install_status_t dd_memory_profiler_start(uint64_t poisson_rate_bytes) {
    os_unfair_lock_lock(&g_lifecycle_lock);
    if (g_profiler_enabled.load(std::memory_order_acquire)) {
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return DD_MEMORY_STATUS_ALREADY_INSTALLED;
    }

    if (g_timebase.denom == 0) {
        mach_timebase_info(&g_timebase);
    }

    malloc_zone_t* zone = malloc_default_zone();
    if (zone == nullptr) {
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return DD_MEMORY_STATUS_FAILED_NO_ZONE;
    }
    // Restart path: we never restore original pointers on stop because
    // another tool may have hooked after us. So a restart legitimately
    // sees our own hooks already in place. Treat that as success and
    // just flip the enable flag back on.
    if (zone->malloc == hooked_malloc) {
        if (!ensure_sample_table_allocated()) {
            os_unfair_lock_unlock(&g_lifecycle_lock);
            return DD_MEMORY_STATUS_FAILED_NO_ZONE;
        }
        start_new_session(poisson_rate_bytes);
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return DD_MEMORY_STATUS_INSTALLED_DIRECT;
    }
    if (!zone_has_default_hooks(zone)) {
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return DD_MEMORY_STATUS_FAILED_COLLISION;
    }

    if (!ensure_sample_table_allocated()) {
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return DD_MEMORY_STATUS_FAILED_NO_ZONE;
    }

    capture_originals(zone);

    dd_memory_install_status_t status = DD_MEMORY_STATUS_INSTALLED_DIRECT;
    vm_prot_t original_prot = 0;
    bool used_mprotect = false;

    if (!probe_zone_writable(zone)) {
        if (!make_zone_writable(zone, &original_prot)) {
            os_unfair_lock_unlock(&g_lifecycle_lock);
            return DD_MEMORY_STATUS_FAILED_READ_ONLY_ZONE;
        }
        used_mprotect = true;
        status = DD_MEMORY_STATUS_INSTALLED_MPROTECT;
    }

    zone->malloc = hooked_malloc;
    zone->calloc = hooked_calloc;
    zone->valloc = hooked_valloc;
    zone->free = hooked_free;
    zone->free_definite_size = hooked_free_definite_size;
    zone->realloc = hooked_realloc;
    if (g_original.memalign_fn != nullptr) {
        zone->memalign = hooked_memalign;
    }

    if (used_mprotect) {
        restore_zone_protection(zone, original_prot);
    }

    start_new_session(poisson_rate_bytes);
    os_unfair_lock_unlock(&g_lifecycle_lock);
    return status;
}

extern "C" bool dd_memory_profiler_start_passive(uint64_t poisson_rate_bytes) {
    os_unfair_lock_lock(&g_lifecycle_lock);
    // Idempotent: if already running (zone-hook or passive), leave the active
    // session and its live set unchanged.
    if (g_profiler_enabled.load(std::memory_order_acquire)) {
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return true;
    }

    if (g_timebase.denom == 0) {
        mach_timebase_info(&g_timebase);
    }

    if (!ensure_sample_table_allocated()) {
        os_unfair_lock_unlock(&g_lifecycle_lock);
        return false;
    }

    start_new_session(poisson_rate_bytes);
    os_unfair_lock_unlock(&g_lifecycle_lock);
    return true;
}

extern "C" void dd_memory_observe_allocation(const void* ptr, uint64_t size, const char* class_name) {
    record_allocation(const_cast<void*>(ptr), static_cast<size_t>(size), class_name);
}

extern "C" void dd_memory_observe_deallocation(const void* ptr) {
    record_free(const_cast<void*>(ptr));
}

extern "C" void dd_memory_profiler_stop(void) {
    // We don't restore the original zone function pointers. Another
    // tool may have replaced them after us; restoring our captured
    // values could overwrite their hooks. Instead, we flip the
    // global enabled flag so our hooks become near-noops.
    os_unfair_lock_lock(&g_lifecycle_lock);
    stop_current_session();
    os_unfair_lock_unlock(&g_lifecycle_lock);
}

extern "C" bool dd_memory_profiler_is_running(void) {
    return g_profiler_enabled.load(std::memory_order_acquire);
}

extern "C" dd_memory_snapshot_t dd_memory_snapshot_capture(void) {
    dd_memory_snapshot_t result = {};
    if (!g_profiler_enabled.load(std::memory_order_acquire)) {
        return result;
    }
    const uint64_t session_generation = g_session_generation.load(std::memory_order_acquire);
    if (g_samples == nullptr) {
        return result;
    }

    size_t capacity = static_cast<size_t>(
        g_live_sampled_allocations.load(std::memory_order_acquire)
    );

    while (true) {
        dd_memory_sample_t* out = nullptr;
        if (capacity > 0) {
            // Snapshot storage must not recursively enter zone hooks if the
            // legacy malloc-zone mode is active.
            const bool previous_reentrancy = tls_in_profiler;
            tls_in_profiler = true;
            out = static_cast<dd_memory_sample_t*>(
                std::calloc(capacity, sizeof(dd_memory_sample_t))
            );
            tls_in_profiler = previous_reentrancy;
            if (out == nullptr) {
                return result;
            }
        }

        // Holding every entry lock creates one exact table instant and
        // prevents slot metadata from being rewritten while it is copied.
        lock_all_sample_entries();

        // A lifecycle transition invalidates the entire table. Validate after
        // acquiring every entry lock so the returned snapshot belongs wholly
        // to one session.
        if (!g_profiler_enabled.load(std::memory_order_acquire)
            || g_session_generation.load(std::memory_order_acquire) != session_generation) {
            unlock_all_sample_entries();
            const bool previous_reentrancy = tls_in_profiler;
            tls_in_profiler = true;
            std::free(out);
            tls_in_profiler = previous_reentrancy;
            return result;
        }

        size_t live_count = 0;
        for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
            if (is_live_address(g_samples[i].addr.load(std::memory_order_relaxed))) {
                live_count += 1;
            }
        }

        if (live_count > capacity) {
            unlock_all_sample_entries();
            const bool previous_reentrancy = tls_in_profiler;
            tls_in_profiler = true;
            std::free(out);
            tls_in_profiler = previous_reentrancy;
            capacity = live_count;
            continue;
        }

        size_t written = 0;
        for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
            const sample_entry& entry = g_samples[i];
            const uint64_t addr = entry.addr.load(std::memory_order_relaxed);
            if (!is_live_address(addr)) {
                continue;
            }
            out[written].addr = addr;
            out[written].size = entry.size;
            out[written].weight = entry.weight;
            out[written].timestamp_ns = entry.timestamp_ns;
            out[written].frame_count = entry.frame_count;
            out[written].class_name = entry.class_name;
            std::memcpy(out[written].frames, entry.frames,
                        sizeof(uint64_t) * SAMPLE_STACK_DEPTH);
            written += 1;
        }

        result.timestamp_ns = monotonic_ns_since_start();
        unlock_all_sample_entries();

        if (written == 0) {
            const bool previous_reentrancy = tls_in_profiler;
            tls_in_profiler = true;
            std::free(out);
            tls_in_profiler = previous_reentrancy;
            return result;
        }

        result.samples = out;
        result.sample_count = written;
        return result;
    }
}

extern "C" void dd_memory_snapshot_destroy(dd_memory_snapshot_t* snapshot) {
    if (snapshot == nullptr || snapshot->samples == nullptr) {
        return;
    }
    const bool previous_reentrancy = tls_in_profiler;
    tls_in_profiler = true;
    std::free(snapshot->samples);
    tls_in_profiler = previous_reentrancy;
    snapshot->samples = nullptr;
    snapshot->sample_count = 0;
}

extern "C" dd_memory_diagnostics_t dd_memory_profiler_diagnostics(void) {
    dd_memory_diagnostics_t d = {};
    d.total_bytes_allocated = g_total_bytes_allocated.load(std::memory_order_relaxed);
    d.total_allocations = g_total_allocations.load(std::memory_order_relaxed);
    d.sampled_allocations = g_sampled_allocations.load(std::memory_order_relaxed);
    d.dropped_samples = g_dropped_samples.load(std::memory_order_relaxed);
    d.sampled_frees = g_sampled_frees.load(std::memory_order_relaxed);
    d.live_sampled_allocations = g_live_sampled_allocations.load(std::memory_order_relaxed);
    d.reentrant_skips = g_reentrant_skips.load(std::memory_order_relaxed);
    d.unsampled_calls = g_unsampled_calls.load(std::memory_order_relaxed);
    return d;
}

// MARK: - Testing API

extern "C" bool dd_memory_test_default_zone_writable(void) {
    return probe_zone_writable(malloc_default_zone());
}

extern "C" void dd_memory_test_reset(void) {
    os_unfair_lock_lock(&g_lifecycle_lock);
    os_unfair_lock_lock(&g_insert_lock);
    g_profiler_enabled.store(false, std::memory_order_release);
    g_session_generation.fetch_add(1, std::memory_order_acq_rel);
    clear_sample_table_locked();
    reset_diagnostics();
    os_unfair_lock_unlock(&g_insert_lock);
    os_unfair_lock_unlock(&g_lifecycle_lock);

    tls_force_next_sample = false;
    tls_bytes_until_sample = 0;
    tls_sampling_generation = 0;
}

extern "C" void dd_memory_test_force_next_sample(void) {
    tls_sampling_generation = g_session_generation.load(std::memory_order_acquire);
    tls_force_next_sample = true;
}

extern "C" uint64_t dd_memory_test_sampled_count(void) {
    return g_sampled_allocations.load(std::memory_order_relaxed);
}

extern "C" uint64_t dd_memory_test_live_count(void) {
    return g_live_sampled_allocations.load(std::memory_order_relaxed);
}

extern "C" uint64_t dd_memory_test_session_generation(void) {
    return g_session_generation.load(std::memory_order_acquire);
}

extern "C" size_t dd_memory_test_bucket_for(const void* ptr) {
    return bucket_for(reinterpret_cast<uint64_t>(ptr));
}

extern "C" bool dd_memory_test_insert_sample(
    const void* ptr,
    uint64_t size,
    uint64_t session_generation
) {
    const insert_result result = insert_sample(
        reinterpret_cast<uint64_t>(ptr),
        size,
        1.0,
        nullptr,
        0,
        nullptr,
        session_generation
    );
    return result == insert_result::inserted;
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
