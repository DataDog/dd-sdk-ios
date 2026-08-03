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
#include <cstring>
#include <functional>
#include <new>
#include <string>
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

/// Aggregation key: unique (resolved stack, class name, source).
struct HeapKey {
    std::vector<uint32_t> loc_ids;
    std::string class_name;   // empty when the sample had no class
    int source = 0;
    bool operator==(const HeapKey& o) const {
        return source == o.source && class_name == o.class_name && loc_ids == o.loc_ids;
    }
};

struct HeapKeyHash {
    size_t operator()(const HeapKey& k) const noexcept {
        size_t seed = k.loc_ids.size();
        for (uint32_t x : k.loc_ids) {
            // FNV-inspired combine.
            seed ^= static_cast<size_t>(x) + 0x9e3779b9u + (seed << 6) + (seed >> 2);
        }
        seed ^= std::hash<std::string>{}(k.class_name) + 0x9e3779b9u + (seed << 6) + (seed >> 2);
        seed ^= static_cast<size_t>(k.source) + 0x9e3779b9u + (seed << 6) + (seed >> 2);
        return seed;
    }
};

/// Accumulated four-value totals per unique key. `alloc_*` come from the
/// per-window allocation log; `inuse_*` from the live-set snapshot. A key can
/// appear in one side only (e.g. a transient allocated and freed within the
/// window has alloc_* > 0 but inuse_* == 0).
struct HeapAccum {
    int64_t alloc_objects = 0;
    int64_t alloc_space   = 0;
    int64_t inuse_objects = 0;
    int64_t inuse_space   = 0;
};

/// Maps a source enum value to its Go-aligned label string.
const char* source_label_value(int source) {
    switch (source) {
        case 1: return "objc";
        case 2: return "swift";
        default: return "zone";
    }
}

/// Resolves each sample's stack and folds its Poisson-unbiased object/byte
/// estimates into `accum`, keyed by (resolved stack, class, source). `is_alloc`
/// selects which pair of totals to grow: the allocation-window totals (`alloc_*`)
/// or the live-set totals (`inuse_*`).
void aggregate_snapshot(const dd_memory_snapshot_t* snapshot,
                        dd::profiler::profile& prof,
                        dd::profiler::binary_image_cache* cache,
                        std::unordered_map<HeapKey, HeapAccum, HeapKeyHash>& accum,
                        bool is_alloc) {
    if (snapshot == nullptr) {
        return;
    }
    for (size_t i = 0; i < snapshot->sample_count; ++i) {
        const dd_memory_sample_t& s = snapshot->samples[i];

        ScopedStackTrace sst(s);
        HeapKey key;
        key.loc_ids = prof.resolve_locations(sst.trace, cache);
        key.class_name = (s.class_name != nullptr) ? std::string(s.class_name) : std::string();
        key.source = static_cast<int>(s.source);

        // Poisson-unbiased estimates: space += round(size * weight),
        // objects += round(weight)  (weight ≈ 1/P).
        const int64_t space   = static_cast<int64_t>(std::llround(
                                    static_cast<double>(s.size) * s.weight));
        const int64_t objects = static_cast<int64_t>(std::llround(s.weight));

        HeapAccum& a = accum[key];
        if (is_alloc) {
            a.alloc_space   += space;
            a.alloc_objects += objects;
        } else {
            a.inuse_space   += space;
            a.inuse_objects += objects;
        }
    }
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// Public C API
// ---------------------------------------------------------------------------

extern "C" {

size_t dd_memory_snapshots_to_pprof(
    const dd_memory_snapshot_t* inuse_snapshot,
    const dd_memory_snapshot_t* alloc_snapshot,
    const char* session_id,
    const char* view_id,
    const char* application_id,
    uint8_t** out_data)
{
    if (out_data) *out_data = nullptr;
    if (!out_data) {
        return 0;
    }
    const size_t inuse_count = inuse_snapshot ? inuse_snapshot->sample_count : 0;
    const size_t alloc_count = alloc_snapshot ? alloc_snapshot->sample_count : 0;
    if (inuse_count == 0 && alloc_count == 0) {
        return 0;
    }

    // ------------------------------------------------------------------
    // 1. Build the profile with the standard heap period (524288 bytes).
    // ------------------------------------------------------------------
    dd::profiler::profile prof(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES);

    // ------------------------------------------------------------------
    // 2. Pre-build the RUM correlation labels (uniform across all samples
    //    — this is a point-in-time snapshot so every sample carries the
    //    same context).  Label keys use Go-aligned names ("session_id",
    //    "view_id", "application_id").  NULL or empty strings are omitted.
    //
    //    Strings are interned via prof.make_string_label() which delegates
    //    to the private intern_string() path — no duplication of interning.
    // ------------------------------------------------------------------
    std::vector<dd::profiler::label_t> rum_labels;
    rum_labels.reserve(3);

    auto non_empty = [](const char* s) -> bool {
        return s != nullptr && s[0] != '\0';
    };

    if (non_empty(session_id)) {
        rum_labels.push_back(prof.make_string_label("session_id", session_id));
    }
    if (non_empty(view_id)) {
        rum_labels.push_back(prof.make_string_label("view_id", view_id));
    }
    if (non_empty(application_id)) {
        rum_labels.push_back(prof.make_string_label("application_id", application_id));
    }

    // ------------------------------------------------------------------
    // 3. Obtain a binary_image_cache the same way the wall-profiling path
    //    does in dd_profiler.cpp::auto_start().
    // ------------------------------------------------------------------
    dd::profiler::binary_image_cache* cache =
        new (std::nothrow) dd::profiler::binary_image_cache();
    if (cache && !cache->load()) {
        delete cache;
        cache = nullptr;
    }

    // ------------------------------------------------------------------
    // 4. Aggregate BOTH snapshots by unique (resolved stack, class, source).
    //    The allocation window feeds alloc_*; the live set feeds inuse_*.
    //    A key present in only one snapshot gets zeros on the other side —
    //    e.g. an object allocated and freed within the window contributes to
    //    alloc_* but not inuse_*, which is exactly what makes the two diverge.
    //
    //    RUM labels are uniform and applied after aggregation, so they do NOT
    //    affect the aggregation key.
    // ------------------------------------------------------------------
    std::unordered_map<HeapKey, HeapAccum, HeapKeyHash> accum;
    aggregate_snapshot(alloc_snapshot, prof, cache, accum, /*is_alloc=*/true);
    aggregate_snapshot(inuse_snapshot, prof, cache, accum, /*is_alloc=*/false);

    delete cache;

    // ------------------------------------------------------------------
    // 5. Emit one sample_t per aggregated stack.
    //
    //    Value order (Go-aligned, matching profile_pprof_pack_heap):
    //      [0] alloc_objects
    //      [1] alloc_space
    //      [2] inuse_objects
    //      [3] inuse_space
    //
    //    alloc_* come from the allocation window; inuse_* from the live set.
    //
    //    RUM correlation labels are appended to every sample (uniform).
    // ------------------------------------------------------------------
    for (auto& [key, a] : accum) {
        dd::profiler::sample_t sample;
        sample.location_ids        = key.loc_ids;
        sample.timestamp_uptime_ns = 0;  // heap samples have no per-sample timestamp
        sample.values = {
            a.alloc_objects,  // alloc_objects
            a.alloc_space,    // alloc_space
            a.inuse_objects,  // inuse_objects
            a.inuse_space,    // inuse_space
        };
        // RUM correlation labels (uniform), plus per-key class_name and source.
        sample.labels = rum_labels;
        if (!key.class_name.empty()) {
            sample.labels.push_back(prof.make_string_label("class_name", key.class_name.c_str()));
        }
        sample.labels.push_back(prof.make_string_label("source", source_label_value(key.source)));
        prof.add_raw_sample(std::move(sample));
    }

    // ------------------------------------------------------------------
    // 6. Serialize with the heap packer and return.
    // ------------------------------------------------------------------
    return dd::profiler::profile_pprof_pack_heap(prof, out_data);
}

size_t dd_memory_snapshot_to_pprof(
    const dd_memory_snapshot_t* snapshot,
    const char* session_id,
    const char* view_id,
    const char* application_id,
    uint8_t** out_data)
{
    // Backward-compatible single-snapshot entry point: alloc_* == inuse_*,
    // both derived from the one snapshot. Kept for callers/tests that don't
    // supply an independent allocation window.
    return dd_memory_snapshots_to_pprof(snapshot, snapshot,
                                        session_id, view_id, application_id,
                                        out_data);
}

} // extern "C"

#endif // __APPLE__ && !TARGET_OS_WATCH
