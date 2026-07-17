/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/**
 * @file memory_to_pprof.cpp
 * @brief Convert a heap snapshot into a serialized heap-pprof buffer.
 *
 * Aggregates live allocations from a `dd_memory_snapshot_t` into a `profile`
 * object and serializes it with `profile_pprof_pack_heap`.  Symbolication
 * reuses the existing `profile::resolve_locations` path (which wraps
 * `intern_frame`) to avoid duplicating any interning logic.
 */

#include "memory_to_pprof.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include "profile.h"
#include "profile_pprof_packer.h"
#include "binary_image_resolver.h"
#include "dd_profiler.h"

#include <cmath>
#include <cstdlib>
#include <new>
#include <unordered_map>
#include <vector>

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

namespace {

/**
 * Build a stack_trace_t (without tid/name/timestamp — not needed for heap
 * symbolication) from the raw instruction-pointer array in a memory sample.
 *
 * The returned frames array is allocated on the stack of the caller's loop
 * body; it is valid only for the lifetime of that iteration.
 */
struct ScopedStackTrace {
    // Reserve the maximum depth the memory profiler can produce.
    stack_frame_t frames[DD_MEMORY_DEFAULT_STACK_DEPTH];
    stack_trace_t trace{};

    explicit ScopedStackTrace(const dd_memory_sample_t& sample) {
        uint32_t count = sample.frame_count < DD_MEMORY_DEFAULT_STACK_DEPTH
                       ? sample.frame_count
                       : DD_MEMORY_DEFAULT_STACK_DEPTH;
        for (uint32_t i = 0; i < count; ++i) {
            // Leave image zeroed — intern_frame resolves it lazily from the cache.
            frames[i].instruction_ptr = sample.frames[i];
            frames[i].image = binary_image_t{};
        }
        trace.tid                    = 0;
        trace.thread_name            = nullptr;
        trace.timestamp              = sample.timestamp_ns;
        trace.sampling_interval_nanos = 0;
        trace.frames                 = frames;
        trace.frame_count            = count;
    }
};

/// Hash for std::vector<uint32_t> so it can be used as an unordered_map key.
struct VectorHash {
    size_t operator()(const std::vector<uint32_t>& v) const noexcept {
        size_t seed = v.size();
        for (uint32_t x : v) {
            // FNV-inspired combine.
            seed ^= static_cast<size_t>(x) + 0x9e3779b9u + (seed << 6) + (seed >> 2);
        }
        return seed;
    }
};

/// Accumulated (inuse_objects, inuse_space) per unique resolved stack.
struct HeapAccum {
    int64_t inuse_objects = 0;
    int64_t inuse_space   = 0;
};

} // anonymous namespace

// ---------------------------------------------------------------------------
// Public C API
// ---------------------------------------------------------------------------

extern "C" {

size_t dd_memory_snapshot_to_pprof(const dd_memory_snapshot_t* snapshot, uint8_t** out_data) {
    if (out_data) *out_data = nullptr;
    if (!snapshot || snapshot->sample_count == 0 || !out_data) {
        return 0;
    }

    // ------------------------------------------------------------------
    // 1. Build the profile with the standard heap period (524288 bytes).
    // ------------------------------------------------------------------
    dd::profiler::profile prof(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES);

    // ------------------------------------------------------------------
    // 2. Obtain a binary_image_cache the same way the wall-profiling path
    //    does in dd_profiler.cpp::auto_start().
    // ------------------------------------------------------------------
    dd::profiler::binary_image_cache* cache =
        new (std::nothrow) dd::profiler::binary_image_cache();
    if (cache && !cache->load()) {
        delete cache;
        cache = nullptr;
    }

    // ------------------------------------------------------------------
    // 3. Resolve every sample's stack and accumulate by unique location
    //    vector.  Identical stacks (same resolved location_ids) are
    //    merged so the pprof emits one sample per unique callsite.
    // ------------------------------------------------------------------
    std::unordered_map<std::vector<uint32_t>, HeapAccum, VectorHash> accum;

    for (size_t i = 0; i < snapshot->sample_count; ++i) {
        const dd_memory_sample_t& s = snapshot->samples[i];

        ScopedStackTrace sst(s);
        std::vector<uint32_t> loc_ids = prof.resolve_locations(sst.trace, cache);

        HeapAccum& a = accum[loc_ids];
        // Poisson-unbiased estimates:
        //   inuse_space  += round(size * weight)
        //   inuse_objects += round(weight)          (weight ≈ 1/P)
        a.inuse_space   += static_cast<int64_t>(std::llround(
                               static_cast<double>(s.size) * s.weight));
        a.inuse_objects += static_cast<int64_t>(std::llround(s.weight));
    }

    delete cache;

    // ------------------------------------------------------------------
    // 4. Emit one sample_t per aggregated stack.
    //
    //    Value order (Go-aligned, matching profile_pprof_pack_heap):
    //      [0] alloc_objects
    //      [1] alloc_space
    //      [2] inuse_objects
    //      [3] inuse_space
    //
    //    NOTE: alloc_* == inuse_* for a single snapshot because we only
    //    have the live set.  True period deltas (allocation events between
    //    two snapshots) are a deferred follow-up and will require a
    //    separate accumulation path.
    // ------------------------------------------------------------------
    for (auto& [loc_ids, a] : accum) {
        dd::profiler::sample_t sample;
        sample.location_ids       = loc_ids;
        sample.timestamp_uptime_ns = 0;  // heap samples have no per-sample timestamp
        // alloc_* == inuse_* (single-snapshot approximation — see note above)
        sample.values = {
            a.inuse_objects,  // alloc_objects
            a.inuse_space,    // alloc_space
            a.inuse_objects,  // inuse_objects
            a.inuse_space,    // inuse_space
        };
        prof.add_raw_sample(std::move(sample));
    }

    // ------------------------------------------------------------------
    // 5. Serialize with the heap packer and return.
    // ------------------------------------------------------------------
    return dd::profiler::profile_pprof_pack_heap(prof, out_data);
}

} // extern "C"

#endif // __APPLE__ && !TARGET_OS_WATCH
