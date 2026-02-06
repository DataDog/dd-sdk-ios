/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "dd_pprof.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include "profile.h"
#include "profile_pprof_packer.h"

// C interface implementation
extern "C" {

dd_pprof_t* dd_pprof_create(uint64_t sampling_interval_ns) {
    try {
        auto* profiler = new dd::profiler::profile(sampling_interval_ns);
        return reinterpret_cast<dd_pprof_t*>(profiler);
    } catch (...) {
        return nullptr;
    }
}

void dd_pprof_destroy(dd_pprof_t* profile) {
    if (profile) {
        delete reinterpret_cast<dd::profiler::profile*>(profile);
    }
}

void dd_pprof_add_samples(dd_pprof_t* profile, const stack_trace_t* traces, size_t count) {
    if (profile && traces && count > 0) {
        reinterpret_cast<dd::profiler::profile*>(profile)->add_samples(traces, count);
    }
}

size_t dd_pprof_serialize(dd_pprof_t* profile, uint8_t** data) {
    if (!profile || !data) return 0;
    return dd::profiler::profile_pprof_pack(*reinterpret_cast<dd::profiler::profile*>(profile), data);
}

void dd_pprof_free_serialized_data(uint8_t* data) {
    if (data) free(data);
}

void dd_pprof_callback(const stack_trace_t* traces, size_t count, void* ctx) {
    dd_pprof_t* profile = static_cast<dd_pprof_t*>(ctx);
    if (profile && traces && count > 0) {
        dd_pprof_add_samples(profile, traces, count);
    }
}

double dd_pprof_get_start_timestamp_s(dd_pprof_t* profile) {
    if (!profile) return 0.0;
    int64_t timestamp = reinterpret_cast<dd::profiler::profile*>(profile)->start_timestamp();
    return static_cast<double>(timestamp) / 1e9; // to seconds
}

double dd_pprof_get_end_timestamp_s(dd_pprof_t* profile) {
    if (!profile) return 0.0;
    int64_t timestamp = reinterpret_cast<dd::profiler::profile*>(profile)->end_timestamp();
    return static_cast<double>(timestamp) / 1e9; // to seconds
}

} // extern "C"
#endif // !TARGET_OS_WATCH
#endif // __APPLE__

