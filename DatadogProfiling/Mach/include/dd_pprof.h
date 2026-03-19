/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_DD_PPROF_H_
#define DD_PROFILER_DD_PPROF_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdint.h>
#include <stddef.h>
#include "mach_profiler.h"

#ifdef __cplusplus
namespace dd::profiler {

class profile;

} // namespace dd:profiler

extern "C" {
#endif

/**
 * Opaque handle to a profile instance
 */
#ifdef __cplusplus
typedef dd::profiler::profile dd_pprof_t;
#else
typedef struct profile dd_pprof_t;
#endif

/**
 * Create a new pprof profile aggregator
 * 
 * @param sampling_interval_ns The sampling interval in nanoseconds
 * @return Pointer to the created profile, or NULL on failure
 */
dd_pprof_t* dd_pprof_create(uint64_t sampling_interval_ns);

/**
 * Destroy a pprof profile aggregator and free all associated memory
 *
 * @param profile Pointer to the profile to destroy
 */
void dd_pprof_destroy(dd_pprof_t* profile);

/**
 * Add stack traces to the profile
 *
 * @param profile Pointer to the profile
 * @param traces Array of stack traces to add
 * @param count Number of traces in the array
 */
void dd_pprof_add_samples(dd_pprof_t* profile, const stack_trace_t* traces, size_t count);

/**
 * Serialize the profile to protobuf format
 *
 * @param profile Pointer to the profile
 * @param data Output parameter for the serialized data (caller must free with dd_pprof_free_serialized_data)
 * @return Size of the serialized data in bytes, or 0 on failure
 */
size_t dd_pprof_serialize(dd_pprof_t* profile, uint8_t** data);

/**
 * Free memory allocated by dd_pprof_serialize
 *
 * @param data Pointer to the data to free
 */
void dd_pprof_free_serialized_data(uint8_t* data);

/**
 * Callback function that forwards stack traces to a dd_pprof_t instance.
 * 
 * Use this with profiler_create() by passing your dd_pprof_t instance as the ctx parameter.
 * 
 * Example:
 *   dd_pprof_t* profile = dd_pprof_create(1000000);
 *   profiler_t* profiler = profiler_create(&config, dd_pprof_callback, profile);
 */
void dd_pprof_callback(const stack_trace_t* traces, size_t count, void* ctx);

/**
 * Get profile start timestamp in seconds since Unix epoch
 *
 * @param profile Pointer to the profile
 * @return Start timestamp in seconds since Unix epoch, or 0.0 if no samples
 */
double dd_pprof_get_start_timestamp_s(dd_pprof_t* profile);

/**
 * Get profile end timestamp in seconds since Unix epoch
 *
 * @param profile Pointer to the profile
 * @return End timestamp in seconds since Unix epoch, or 0.0 if no samples
 */
double dd_pprof_get_end_timestamp_s(dd_pprof_t* profile);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_DD_PPROF_H_
