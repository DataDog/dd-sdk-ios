/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_to_pprof.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include "binary_image_resolver.h"
#include "poisson_allocation_sampler.h"
#include "profile.h"
#include "profile_pprof_packer.h"

#include <cmath>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace {

struct heap_stack_trace {
    stack_frame_t frames[DD_MEMORY_LIVE_SET_MAX_FRAMES]{};
    stack_trace_t trace{};

    explicit heap_stack_trace(const dd_memory_aggregation_key_t &key) {
        trace.frame_count = key.frame_count < DD_MEMORY_LIVE_SET_MAX_FRAMES
                          ? key.frame_count : DD_MEMORY_LIVE_SET_MAX_FRAMES;
        for (uint32_t i = 0; i < trace.frame_count; ++i) {
            frames[i].instruction_ptr = key.frames[i];
        }
        trace.frames = frames;
    }
};

int64_t rounded_total(double total) {
    if (!(total > 0)) {
        return 0;
    }
    constexpr int64_t maximum = std::numeric_limits<int64_t>::max();
    if (total >= static_cast<double>(maximum)) {
        return maximum;
    }
    return std::llround(total);
}

const char *source_label(dd_memory_live_sample_source_t source) {
    switch (source) {
        case DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC: return "objc";
        case DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT: return "swift";
        default: return "zone";
    }
}

std::string allocation_class(const dd_memory_aggregation_key_t &key) {
    if (key.source == DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT) {
        if (key.swift_metadata && key.swift_name_resolver) {
            const auto name = key.swift_name_resolver(key.swift_metadata);
            if (name.data && name.length > 0) {
                return std::string(name.data, name.length);
            }
        }
        return {};
    }
    return key.class_name ? key.class_name : "";
}

} // namespace

extern "C" size_t dd_memory_aggregates_to_pprof(
    const dd_memory_aggregation_view_t *view,
    const char *session_id,
    const char *view_id,
    const char *application_id,
    uint8_t **out_data) {
    if (!out_data) {
        return 0;
    }
    *out_data = nullptr;
    if (!view || !view->samples || view->count == 0) {
        return 0;
    }

    try {
        dd::profiler::profile prof(dd::profiler::poisson_allocation_sampler::sampling_interval());
        std::vector<dd::profiler::label_t> rum_labels;
        rum_labels.reserve(3);
        if (session_id && session_id[0]) {
            rum_labels.push_back(prof.make_string_label("session_id", session_id));
        }
        if (view_id && view_id[0]) {
            rum_labels.push_back(prof.make_string_label("view_id", view_id));
        }
        if (application_id && application_id[0]) {
            rum_labels.push_back(prof.make_string_label("application_id", application_id));
        }

        auto cache = std::make_unique<dd::profiler::binary_image_cache>();
        if (!cache->load()) {
            cache.reset();
        }

        for (size_t i = 0; i < view->count; ++i) {
            const auto &aggregate = view->samples[i];
            heap_stack_trace stack(aggregate.key);
            dd::profiler::sample_t sample;
            sample.location_ids = prof.resolve_locations(stack.trace, cache.get());
            sample.timestamp_uptime_ns = 0;
            sample.values = {
                rounded_total(aggregate.alloc_objects),
                rounded_total(aggregate.alloc_space),
                rounded_total(aggregate.inuse_objects),
                rounded_total(aggregate.inuse_space),
            };
            sample.labels = rum_labels;
            const auto class_name = allocation_class(aggregate.key);
            if (!class_name.empty()) {
                sample.labels.push_back(prof.make_string_label("allocation class", class_name));
            }
            sample.labels.push_back(prof.make_string_label("source", source_label(aggregate.key.source)));
            prof.add_raw_sample(std::move(sample));
        }
        return dd::profiler::profile_pprof_pack_heap(prof, out_data);
    } catch (...) {
        return 0;
    }
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
