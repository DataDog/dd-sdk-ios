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
#include <mach/mach_time.h>
#include <malloc/malloc.h>
#include <limits>
#include <new>
#include <os/lock.h>
#include <pthread.h>
#include <random>
#include <sys/mman.h>

// =====================================================================
// Memory Profiler — passive Poisson sampler (RUM-16460)
//
// Owns the sampled live-allocation table, the per-window allocation log,
// and heap snapshot capture. Allocations and deallocations are reported
// into this sampler by the interception paths (objc_alloc_hook for
// NSObject-rooted allocations, swift_alloc_hook for pure-Swift classes);
// this file installs no interception itself.
//
// Implementation overview:
//   - Reporting funnels through record_allocation()/record_free(), which
//     check a global enabled flag and a per-thread reentrancy guard
//     (tls_in_profiler) before doing any work, so allocations triggered by
//     our own backtrace()/table insertion cannot recurse.
//   - Poisson sampling is per-thread: each thread keeps a byte counter and
//     decrements on every allocation. When the counter falls to zero, the
//     allocation is sampled and a new threshold drawn from exp(B).
//   - Sampled allocations are stored in a fixed-size, pre-allocated,
//     mmap-backed hash table. Slot metadata is synchronized and
//     snapshot-consistent; we never call malloc from inside the sampler
//     (would recurse) or grow the table at runtime.
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

/// Capacity of the per-window allocation log that feeds `alloc_*`.
/// One entry per sampled allocation observed during the current emission
/// window (independent of the live-set table, which tracks `inuse_*`). Sized
/// like the live table; overflow drops with a counter rather than growing.
constexpr size_t ALLOC_WINDOW_CAPACITY = 4096;
static_assert(
    (ALLOC_WINDOW_CAPACITY & (ALLOC_WINDOW_CAPACITY - 1)) == 0,
    "The alloc-window capacity must remain a power of two"
);

/// Occupancy fraction at which back-pressure first widens the interval.
///
/// Below this, the fixed 512 KB base rate is in force and behavior is
/// identical to a non-adaptive sampler. The trigger is deliberately at half
/// capacity rather than nearer the top: once a structure is full the excess is
/// already unrecoverable, and the schedule below needs enough remaining
/// entries to spend on successive doublings.
constexpr double PRESSURE_FIRST_STEP_FRACTION = 0.50;

/// Spacing between successive widening steps, as a fraction of capacity.
///
/// Evenly spaced marks combined with a doubling multiplier is what makes the
/// window's reach grow exponentially: each 5% slice of entries covers twice
/// the bytes the previous slice did. The obvious alternative — stepping when
/// half the *remaining* headroom is consumed — converges on capacity too fast
/// and buys only a constant number of bytes per step, which is nowhere near
/// enough for a pathological allocator.
constexpr double PRESSURE_STEP_SPACING_FRACTION = 0.05;

/// Occupancy fraction at or below which a completed window narrows the
/// interval one step back toward the base rate.
///
/// The gap between this and PRESSURE_FIRST_STEP_FRACTION is hysteresis.
/// Without it, a widened interval would empty the next window, immediately
/// narrow, refill, and oscillate — halving effective resolution every other
/// window for no benefit. Steady load that settles between the two fractions
/// holds its interval indefinitely, which is the intended resting state.
constexpr double PRESSURE_RELIEF_FRACTION = 0.30;

/// Ceiling on the interval multiplier. Mirrors the public contract.
constexpr uint64_t MAX_RATE_MULTIPLIER = DD_MEMORY_MAX_RATE_MULTIPLIER;

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
    /// Interception path that recorded this sample.
    dd_memory_source_t source{DD_MEMORY_SOURCE_ZONE};
};

// MARK: - Global state

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

/// Per-window allocation log feeding `alloc_*`. A plain array of public sample
/// records (no per-entry lock — only ever read/written under `g_insert_lock`),
/// pre-allocated once with `mmap`. `g_alloc_window_count` is the number of valid
/// entries in the current window; it is reset to 0 at window capture and at
/// session start. Overflow increments `g_alloc_window_dropped` instead of growing.
dd_memory_sample_t* g_alloc_window = nullptr;
size_t g_alloc_window_count = 0;

/// Mach timebase converted to nanoseconds — cached after first use.
mach_timebase_info_data_t g_timebase = {};

/// Profiler start time in mach ticks; sample timestamps are deltas
/// from this anchor.
std::atomic<uint64_t> g_start_ticks{0};

/// Configured Poisson sampling rate (mean bytes between samples). Set at
/// session start and immutable for the session's lifetime; this is the base
/// the back-pressure multiplier is applied to, and the floor of the effective
/// rate.
std::atomic<uint64_t> g_poisson_rate_bytes{DD_MEMORY_POISSON_DEFAULT_RATE_BYTES};

/// Sampling rate actually in force: `g_poisson_rate_bytes * g_rate_multiplier`.
/// Read once per observed allocation on the hot path, so it is cached here as
/// a product rather than recomputed.
std::atomic<uint64_t> g_effective_rate_bytes{DD_MEMORY_POISSON_DEFAULT_RATE_BYTES};

/// Power-of-two back-pressure multiplier in [1, MAX_RATE_MULTIPLIER].
/// Written only under `g_insert_lock`.
uint64_t g_rate_multiplier = 1;

/// Occupancy at which the next widening step fires. Recomputed after each
/// step so successive steps consume half the remaining headroom, and reset to
/// `PRESSURE_STEP_FRACTION * capacity` when a window drains. Written only
/// under `g_insert_lock`.
size_t g_pressure_step_threshold = 0;

/// Highest occupancy observed this session. Writes are already serialized by
/// `g_insert_lock`, but the storage is atomic so the public diagnostics getter
/// can read it without taking that lock — `os_unfair_lock` is not recursive,
/// and a public accessor that grabs the insert lock would deadlock any future
/// caller that reads diagnostics from inside the sampled path.
std::atomic<uint64_t> g_occupancy_high_water{0};

/// Test-only: makes the passive start fail so the fail-closed path is reachable.
/// Always false in production.
std::atomic<bool> g_test_force_start_failure{false};

/// Whether occupancy-driven back-pressure may adjust the interval. Always true
/// in production; tests clear it to pin the sampler to its base rate so the
/// same workload can be measured with and without adaptation.
std::atomic<bool> g_pressure_adaptation_enabled{true};

// MARK: - Diagnostics

std::atomic<uint64_t> g_total_bytes_allocated{0};
std::atomic<uint64_t> g_total_allocations{0};
std::atomic<uint64_t> g_sampled_allocations{0};
std::atomic<uint64_t> g_dropped_samples{0};
std::atomic<uint64_t> g_alloc_window_dropped{0};
std::atomic<uint64_t> g_sampled_frees{0};
std::atomic<uint64_t> g_live_sampled_allocations{0};
std::atomic<uint64_t> g_reentrant_skips{0};
std::atomic<uint64_t> g_unsampled_calls{0};
std::atomic<uint64_t> g_rate_widen_events{0};
std::atomic<uint64_t> g_rate_narrow_events{0};

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

/// The effective rate in force when `tls_bytes_until_sample` was drawn.
///
/// A sample's weight must be derived from the interval that governed its
/// inclusion probability, NOT from whatever the interval happens to be when
/// the sample fires. Those are the same number only while the rate is fixed.
/// Under back-pressure they diverge: a counter that ticked down under the
/// 512 KB base can fire after a burst has widened the interval to 8 MB, and
/// weighting it at 8 MB would overstate that sample 16-fold. Pinning the draw
/// rate per thread keeps every weight matched to its own draw, which is what
/// makes a varying interval unbiased rather than merely plausible.
thread_local uint64_t tls_threshold_rate_bytes = 0;

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

// MARK: - Back-pressure rate control

/// Recomputes the cached effective rate from the base rate and multiplier.
/// Caller must hold `g_insert_lock`.
void publish_effective_rate_locked() {
    const uint64_t base = g_poisson_rate_bytes.load(std::memory_order_relaxed);
    g_effective_rate_bytes.store(base * g_rate_multiplier, std::memory_order_release);
}

/// Entries between successive widening steps; at least one so the schedule
/// always makes progress even at small capacities.
constexpr size_t pressure_step_spacing() {
    const size_t spacing =
        static_cast<size_t>(ALLOC_WINDOW_CAPACITY * PRESSURE_STEP_SPACING_FRACTION);
    return spacing > 0 ? spacing : 1;
}

/// Occupancy at which the first widening step fires.
constexpr size_t pressure_first_step() {
    return static_cast<size_t>(ALLOC_WINDOW_CAPACITY * PRESSURE_FIRST_STEP_FRACTION);
}

/// Resets rate control to the configured base. Caller must hold
/// `g_insert_lock`.
void reset_rate_control_locked() {
    g_rate_multiplier = 1;
    g_pressure_step_threshold = pressure_first_step();
    g_occupancy_high_water.store(0, std::memory_order_relaxed);
    publish_effective_rate_locked();
}

/// Widening half of the controller, called on the sampled slow path once the
/// allocation has been admitted to the window. Caller must hold
/// `g_insert_lock`.
///
/// `occupancy` is the greater of the two fixed-capacity structures' fill
/// levels, since either one saturating causes data loss and both share a
/// capacity.
///
/// The schedule is a doubling of the interval at every 5% of capacity past the
/// halfway mark, which makes each successive slice of entries cover twice the
/// bytes of the one before it. With a 4096-entry window and a 256x ceiling
/// that gives a single window a reach of roughly 100 GB of allocation before
/// it can saturate — about 1.7 GB/s sustained across a 60s emission window,
/// comfortably past any allocation rate a client app survives — while a
/// workload that merely brushes the halfway mark pays exactly one doubling.
///
/// The loop (rather than a single step) matters because `occupancy` can jump
/// by more than one entry between calls: the live-table count moves
/// independently of the window count, so the schedule has to be able to catch
/// up rather than trail a fast-moving signal by several steps.
void note_pressure_locked(size_t occupancy) {
    if (occupancy > g_occupancy_high_water.load(std::memory_order_relaxed)) {
        g_occupancy_high_water.store(occupancy, std::memory_order_relaxed);
    }

    if (!g_pressure_adaptation_enabled.load(std::memory_order_relaxed)) {
        return;
    }

    bool stepped = false;
    while (occupancy >= g_pressure_step_threshold && g_rate_multiplier < MAX_RATE_MULTIPLIER) {
        g_rate_multiplier *= 2;
        g_pressure_step_threshold += pressure_step_spacing();
        g_rate_widen_events.fetch_add(1, std::memory_order_relaxed);
        stepped = true;
    }
    if (stepped) {
        publish_effective_rate_locked();
    }
}

/// Narrowing half of the controller, called once per window when the window
/// drains. Caller must hold `g_insert_lock`.
///
/// A window that completed comfortably under the relief threshold is evidence
/// the widened interval is no longer needed, so we step back one notch — one
/// per window, not straight to the base, so a burst that is merely pausing
/// does not immediately re-saturate. Recovery from the 256x ceiling therefore
/// takes 8 quiet windows, which the anti-ratchet test pins.
void relieve_pressure_locked(size_t final_occupancy) {
    g_pressure_step_threshold = pressure_first_step();

    if (!g_pressure_adaptation_enabled.load(std::memory_order_relaxed) || g_rate_multiplier <= 1) {
        return;
    }
    // Relief must be judged on the same signal widening reacts to: the greater
    // of the two fixed-capacity structures. Only the window drains each
    // emission — the live table does not, and a large long-lived sampled set
    // holds it near capacity indefinitely. Narrowing on the drained window
    // alone would step the interval back down every window while the live table
    // stayed saturated, so drop-new would go on censoring `inuse_*` at exactly
    // the rate the controller had already widened to escape. Both structures
    // share a capacity, so one relief fraction covers them.
    const size_t live_occupancy = static_cast<size_t>(
        g_live_sampled_allocations.load(std::memory_order_relaxed)
    );
    const size_t occupancy = final_occupancy > live_occupancy ? final_occupancy : live_occupancy;
    if (occupancy > static_cast<size_t>(ALLOC_WINDOW_CAPACITY * PRESSURE_RELIEF_FRACTION)) {
        return;
    }

    g_rate_multiplier /= 2;
    g_rate_narrow_events.fetch_add(1, std::memory_order_relaxed);
    publish_effective_rate_locked();
}

// MARK: - Live-sample table

constexpr uint64_t EMPTY_SLOT = 0;
constexpr uint64_t TOMBSTONE_SLOT = 1;

/// Maximum slots a hash probe may visit before giving up.
///
/// A removal leaves a TOMBSTONE so colliding keys keep their probe chain, and a
/// slot never returns to EMPTY within a session (EMPTY -> occupied -> TOMBSTONE
/// -> occupied ...). The count of EMPTY slots is therefore monotonically
/// non-increasing, so a probe that terminates only on EMPTY degrades over the
/// process lifetime: once churn has touched every bucket, a lookup miss would
/// scan the whole table. Every free in the process goes through `remove_sample`,
/// the overwhelming majority of them misses, so that cost is unacceptable on a
/// continuously running profiler.
///
/// Bounding the probe caps a miss at a fixed cost. Insert and remove MUST use
/// the same bound: insert never places an entry further than this from its
/// bucket, so remove is guaranteed to find anything insert admitted. Exhausting
/// the probe on insert counts as a drop (`dropped_samples`), which censors
/// `inuse_*` — permitted by the design — rather than corrupting it.
constexpr size_t MAX_PROBE_DISTANCE = 32;
static_assert(MAX_PROBE_DISTANCE <= SAMPLE_TABLE_CAPACITY,
              "probe bound cannot exceed the table");

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
                            const char* class_name, dd_memory_source_t source,
                            uint64_t session_generation) {
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

    // Record the allocation into the per-window log that feeds `alloc_*`. This
    // happens BEFORE live-table admission on purpose: a drop-new on the live
    // table censors `inuse_*` but must never erase the allocation's `alloc_*`
    // contribution. Guarded by the already-held g_insert_lock (no per-entry lock).
    if (g_alloc_window != nullptr) {
        if (g_alloc_window_count < ALLOC_WINDOW_CAPACITY) {
            dd_memory_sample_t& rec = g_alloc_window[g_alloc_window_count++];
            rec.addr = addr;
            rec.size = size;
            rec.weight = weight;
            rec.class_name = class_name;
            rec.source = source;
            rec.timestamp_ns = monotonic_ns_since_start();
            const uint32_t n = (frame_count > SAMPLE_STACK_DEPTH) ? SAMPLE_STACK_DEPTH : frame_count;
            std::memset(rec.frames, 0, sizeof(rec.frames));
            if (n > 0) {
                std::memcpy(rec.frames, frames, n * sizeof(uint64_t));
            }
            rec.frame_count = n;
        } else {
            g_alloc_window_dropped.fetch_add(1, std::memory_order_relaxed);
        }

        // Answer back-pressure from whichever fixed-capacity structure is
        // closer to saturating. Runs on the sampled slow path only — one
        // comparison per sample, not per allocation — and the widened interval
        // takes effect on the next threshold draw.
        const size_t live_occupancy = static_cast<size_t>(
            g_live_sampled_allocations.load(std::memory_order_relaxed)
        );
        note_pressure_locked(
            g_alloc_window_count > live_occupancy ? g_alloc_window_count : live_occupancy
        );
    }

    size_t available_idx = SAMPLE_TABLE_CAPACITY;
    const size_t start = bucket_for(addr);

    // Bounded probe — see MAX_PROBE_DISTANCE. Must match `remove_sample`.
    for (size_t i = 0; i < MAX_PROBE_DISTANCE; ++i) {
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
    entry.source = source;

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
    // Bounded probe — see MAX_PROBE_DISTANCE. Must match `insert_sample`, which
    // never places an entry beyond this distance from its bucket, so exhausting
    // the bound here proves the address was never admitted.
    for (size_t i = 0; i < MAX_PROBE_DISTANCE; ++i) {
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
        entry.source = DD_MEMORY_SOURCE_ZONE;
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
/// @param resolver Optional callback producing the class name, invoked ONLY when
///                 the allocation is sampled. Callers whose name lookup is more
///                 than a metadata read (the Swift path resolves and caches a
///                 demangled type name) must pass this instead of `class_name`
///                 so the cost lands on the sampled path — roughly one
///                 allocation in `poisson_rate_bytes` — not on every allocation
///                 in the process. Ignored when `class_name` is non-null.
/// @param resolver_context Opaque argument forwarded to `resolver`.
void* record_allocation(void* ptr, size_t size, const char* class_name = nullptr,
                        dd_memory_source_t source = DD_MEMORY_SOURCE_ZONE,
                        dd_memory_class_name_resolver_t resolver = nullptr,
                        void* resolver_context = nullptr) {
    if (ptr == nullptr) {
        return ptr;
    }

    // The acquire pairs with session start, publishing the table, sampling
    // configuration, and generation before this hook observes them.
    if (!g_profiler_enabled.load(std::memory_order_acquire)) {
        return ptr;
    }
    const uint64_t session_generation = g_session_generation.load(std::memory_order_acquire);
    const uint64_t poisson_rate_bytes = g_effective_rate_bytes.load(std::memory_order_acquire);

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
        tls_threshold_rate_bytes = poisson_rate_bytes;
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

    // Weight this sample at the rate its own countdown was drawn under, then
    // rearm at whatever rate is in force now. Under a fixed rate the two are
    // identical; under back-pressure this is what keeps the estimator
    // unbiased across an interval change. See tls_threshold_rate_bytes.
    const uint64_t draw_rate_bytes = tls_threshold_rate_bytes != 0
        ? tls_threshold_rate_bytes
        : poisson_rate_bytes;
    tls_threshold_rate_bytes = poisson_rate_bytes;
    tls_bytes_until_sample = draw_next_threshold(poisson_rate_bytes);

    // Enter the sampling slow path. Any allocation made by backtrace()
    // or the table machinery from here on must short-circuit via the
    // tls_in_profiler check above.
    tls_in_profiler = true;

    // Resolve the class name now that the allocation is known to be sampled.
    // Deliberately inside the reentrancy guard: a resolver may dlsym or touch
    // runtime caches, and any allocation it triggers must short-circuit rather
    // than recurse into this hook.
    if (class_name == nullptr && resolver != nullptr) {
        class_name = resolver(resolver_context);
    }

    uint64_t frames[SAMPLE_STACK_DEPTH];
    const uint32_t frame_count = capture_backtrace(frames, SAMPLE_STACK_DEPTH);
    const double weight = poisson_weight_for_size(size, draw_rate_bytes);
    insert_sample(
        reinterpret_cast<uint64_t>(ptr),
        size,
        weight,
        frames,
        frame_count,
        class_name,
        source,
        session_generation
    );
    tls_in_profiler = false;
    return ptr;
}

/// Per-free bookkeeping. Removes the entry from the live set if we
/// were tracking it. Unsampled frees — the overwhelming majority — cost at most
/// MAX_PROBE_DISTANCE slot reads in `remove_sample`, and typically far fewer
/// while empty slots remain. The bound matters: empty slots only ever become
/// occupied or tombstoned within a session, so an unbounded probe would grow
/// towards a full-table scan on every free as the process runs.
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

// MARK: - Installation

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
    // Per-window allocation log. dd_memory_sample_t is a plain C struct, so the
    // zero-filled mmap pages are already a valid initial state — no placement new.
    //
    // Mapped BEFORE publishing g_samples so this function is all-or-nothing. The
    // early-out at the top keys off g_samples alone, so publishing it first and
    // then failing here would latch a half-initialised state: every later call
    // would short-circuit and return true, dd_memory_profiler_start_passive
    // would report success with a null alloc window, and the profiler would run
    // permanently unable to record alloc_* — with back-pressure disabled too,
    // since note_pressure_locked is only reached when the window exists. Silent
    // and unrecoverable for the life of the process.
    const size_t alloc_bytes = sizeof(dd_memory_sample_t) * ALLOC_WINDOW_CAPACITY;
    void* alloc_mem = mmap(nullptr, alloc_bytes, PROT_READ | PROT_WRITE,
                           MAP_ANON | MAP_PRIVATE, -1, 0);
    if (alloc_mem == MAP_FAILED) {
        // Release the sample table rather than leaking it: this call failed, and
        // the next one must start from a clean slate to have any chance.
        munmap(mem, bytes);
        return false;
    }

    // mmap provides storage, but C++ object lifetime still begins through
    // placement construction so atomics and per-entry locks are initialized.
    sample_entry* samples = static_cast<sample_entry*>(mem);
    for (size_t i = 0; i < SAMPLE_TABLE_CAPACITY; ++i) {
        new (&samples[i]) sample_entry();
    }

    g_alloc_window = static_cast<dd_memory_sample_t*>(alloc_mem);
    g_alloc_window_count = 0;
    // Published last: g_samples is the "initialised" flag for the early-out.
    g_samples = samples;
    return true;
}

void reset_diagnostics() {
    g_total_bytes_allocated.store(0, std::memory_order_relaxed);
    g_total_allocations.store(0, std::memory_order_relaxed);
    g_sampled_allocations.store(0, std::memory_order_relaxed);
    g_dropped_samples.store(0, std::memory_order_relaxed);
    g_alloc_window_dropped.store(0, std::memory_order_relaxed);
    g_sampled_frees.store(0, std::memory_order_relaxed);
    g_reentrant_skips.store(0, std::memory_order_relaxed);
    g_unsampled_calls.store(0, std::memory_order_relaxed);
    g_rate_widen_events.store(0, std::memory_order_relaxed);
    g_rate_narrow_events.store(0, std::memory_order_relaxed);
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
    g_alloc_window_count = 0;
    reset_diagnostics();
    reset_rate_control_locked();
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

extern "C" bool dd_memory_profiler_start_passive(uint64_t poisson_rate_bytes) {
    // Test-only: simulate a sampler that cannot start. Relaxed load of a flag
    // that is false in production, so this costs nothing on the real path.
    if (g_test_force_start_failure.load(std::memory_order_relaxed)) {
        return false;
    }

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
    record_allocation(const_cast<void*>(ptr), static_cast<size_t>(size), class_name, DD_MEMORY_SOURCE_OBJC);
}

extern "C" void dd_memory_observe_allocation_with_source(const void* ptr, uint64_t size,
                                                         const char* class_name,
                                                         dd_memory_source_t source) {
    record_allocation(const_cast<void*>(ptr), static_cast<size_t>(size), class_name, source);
}

extern "C" void dd_memory_observe_allocation_resolved(const void* ptr, uint64_t size,
                                                      dd_memory_class_name_resolver_t resolver,
                                                      void* context,
                                                      dd_memory_source_t source) {
    record_allocation(const_cast<void*>(ptr), static_cast<size_t>(size),
                      /*class_name=*/nullptr, source, resolver, context);
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
            out[written].source = entry.source;
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

extern "C" dd_memory_snapshot_t dd_memory_alloc_window_capture(void) {
    dd_memory_snapshot_t result = {};
    if (!g_profiler_enabled.load(std::memory_order_acquire)) {
        return result;
    }

    os_unfair_lock_lock(&g_insert_lock);
    const size_t count = g_alloc_window_count;
    if (g_alloc_window == nullptr || count == 0) {
        // Nothing this window; still reset so the next window starts clean.
        g_alloc_window_count = 0;
        relieve_pressure_locked(count);
        os_unfair_lock_unlock(&g_insert_lock);
        return result;
    }

    // Copy the window out, then reset it. Guard reentrancy around calloc in case
    // the legacy malloc-zone hooks are active (mirrors dd_memory_snapshot_capture).
    const bool previous_reentrancy = tls_in_profiler;
    tls_in_profiler = true;
    dd_memory_sample_t* out = static_cast<dd_memory_sample_t*>(
        std::calloc(count, sizeof(dd_memory_sample_t))
    );
    tls_in_profiler = previous_reentrancy;
    if (out == nullptr) {
        os_unfair_lock_unlock(&g_insert_lock);
        return result;
    }

    std::memcpy(out, g_alloc_window, count * sizeof(dd_memory_sample_t));
    g_alloc_window_count = 0;  // window drained; next window accumulates fresh
    // The drained fill level is this window's verdict on whether the current
    // interval is still needed. Narrowing is deliberately once-per-window,
    // never per-insert, so relief cannot race the burst that caused it.
    relieve_pressure_locked(count);
    result.samples = out;
    result.sample_count = count;
    result.timestamp_ns = monotonic_ns_since_start();
    os_unfair_lock_unlock(&g_insert_lock);
    return result;
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
    d.dropped_alloc_records = g_alloc_window_dropped.load(std::memory_order_relaxed);
    d.sampled_frees = g_sampled_frees.load(std::memory_order_relaxed);
    d.live_sampled_allocations = g_live_sampled_allocations.load(std::memory_order_relaxed);
    d.reentrant_skips = g_reentrant_skips.load(std::memory_order_relaxed);
    d.unsampled_calls = g_unsampled_calls.load(std::memory_order_relaxed);
    d.base_rate_bytes = g_poisson_rate_bytes.load(std::memory_order_relaxed);
    d.effective_rate_bytes = g_effective_rate_bytes.load(std::memory_order_acquire);
    d.rate_widen_events = g_rate_widen_events.load(std::memory_order_relaxed);
    d.rate_narrow_events = g_rate_narrow_events.load(std::memory_order_relaxed);
    d.occupancy_high_water = g_occupancy_high_water.load(std::memory_order_relaxed);
    return d;
}

// MARK: - Testing API

extern "C" void dd_memory_test_force_start_failure(bool enabled) {
    g_test_force_start_failure.store(enabled, std::memory_order_relaxed);
}

extern "C" void dd_memory_test_set_pressure_adaptation(bool enabled) {
    g_pressure_adaptation_enabled.store(enabled, std::memory_order_relaxed);
}

extern "C" void dd_memory_test_reset(void) {
    g_test_force_start_failure.store(false, std::memory_order_relaxed);
    g_pressure_adaptation_enabled.store(true, std::memory_order_relaxed);
    os_unfair_lock_lock(&g_lifecycle_lock);
    os_unfair_lock_lock(&g_insert_lock);
    g_profiler_enabled.store(false, std::memory_order_release);
    g_session_generation.fetch_add(1, std::memory_order_acq_rel);
    clear_sample_table_locked();
    g_alloc_window_count = 0;
    reset_diagnostics();
    reset_rate_control_locked();
    os_unfair_lock_unlock(&g_insert_lock);
    os_unfair_lock_unlock(&g_lifecycle_lock);

    tls_force_next_sample = false;
    tls_bytes_until_sample = 0;
    tls_sampling_generation = 0;
    tls_threshold_rate_bytes = 0;
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
        DD_MEMORY_SOURCE_ZONE,
        session_generation
    );
    return result == insert_result::inserted;
}

extern "C" dd_memory_source_t dd_memory_test_sample_source(const void* ptr) {
    if (g_samples == nullptr) {
        return DD_MEMORY_SOURCE_ZONE;
    }
    const uint64_t addr = reinterpret_cast<uint64_t>(ptr);
    if (!is_live_address(addr)) {
        return DD_MEMORY_SOURCE_ZONE;
    }
    const size_t start = bucket_for(addr);
    // Same bound as insert/remove so the test helper agrees with production.
    for (size_t i = 0; i < MAX_PROBE_DISTANCE; ++i) {
        const size_t idx = (start + i) % SAMPLE_TABLE_CAPACITY;
        sample_entry& entry = g_samples[idx];
        const uint64_t current = entry.addr.load(std::memory_order_acquire);
        if (current == EMPTY_SLOT) {
            return DD_MEMORY_SOURCE_ZONE;
        }
        if (current == addr) {
            os_unfair_lock_lock(&entry.lock);
            const dd_memory_source_t s = entry.source;
            os_unfair_lock_unlock(&entry.lock);
            return s;
        }
    }
    return DD_MEMORY_SOURCE_ZONE;
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
