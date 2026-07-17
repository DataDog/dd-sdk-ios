/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_DD_PPROF_TESTING_H_
#define DD_PROFILER_DD_PPROF_TESTING_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stddef.h>
#include "dd_pprof.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Returns the number of deduplicated samples stored in the profile.
 *
 * @param profile Profile pointer or NULL.
 * @return Sample count, or 0 if `profile` is NULL.
 *
 * @warning FOR TESTING USE ONLY - Not intended for production environments
 */
size_t dd_pprof_sample_count(dd_pprof_t* profile);

/**
 * Appends a raw heap sample directly to the profile without resolving any
 * binary images.  This bypasses the stack_trace_t ingestion path so tests can
 * inject exact (alloc_objects, alloc_space, inuse_objects, inuse_space) tuples.
 *
 * @param profile          Profile pointer or NULL (no-op if NULL).
 * @param location_id      1-based location ID to associate with the sample.
 * @param alloc_objects    Number of allocated objects.
 * @param alloc_space      Bytes allocated.
 * @param inuse_objects    Number of in-use objects.
 * @param inuse_space      Bytes in use.
 *
 * @warning FOR TESTING USE ONLY - Not intended for production environments
 */
void dd_pprof_add_heap_sample_for_testing(
    dd_pprof_t* profile,
    uint32_t location_id,
    int64_t alloc_objects,
    int64_t alloc_space,
    int64_t inuse_objects,
    int64_t inuse_space
);

/**
 * Serializes the profile using the heap packing path (four sample types:
 * alloc_objects/count, alloc_space/bytes, inuse_objects/count, inuse_space/bytes).
 *
 * @param profile Pointer to the profile, or NULL.
 * @param data    Output parameter for the serialized data (caller must free with
 *                dd_pprof_free_serialized_data).
 * @return Size of the serialized data in bytes, or 0 on failure.
 *
 * @warning FOR TESTING USE ONLY - Not intended for production environments
 */
size_t dd_pprof_serialize_heap_for_testing(dd_pprof_t* profile, uint8_t** data);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_DD_PPROF_TESTING_H_
