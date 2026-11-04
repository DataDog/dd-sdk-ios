/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_TO_PPROF_H_
#define DD_MEMORY_TO_PPROF_H_

#include "memory_allocation_window.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#ifdef __cplusplus
extern "C" {
#endif

/// Serializes a captured allocation window as heap pprof. Each aggregate supplies
/// independent alloc_objects, alloc_space, inuse_objects and inuse_space totals;
/// fractional totals are rounded only when creating the serialized sample.
/// The period is the Poisson sampler's fixed 512 KiB interval, in space/bytes.
///
/// Resolves stacks and Swift class names on the background profiling queue,
/// outside allocation observers and Mach thread suspension. The view and its
/// borrowed class-name bytes must remain valid until this call returns.
/// Nonempty RUM IDs become session_id, view_id and application_id string labels
/// on every sample; NULL or empty IDs are omitted.
///
/// Returns zero for empty/invalid input or failure and clears *out_data. On
/// success, the caller owns *out_data and must release it with free().
size_t dd_memory_aggregates_to_pprof(
    const dd_memory_aggregation_view_t *view,
    const char *session_id,
    const char *view_id,
    const char *application_id,
    uint8_t **out_data);

#ifdef __cplusplus
}
#endif

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
#endif // DD_MEMORY_TO_PPROF_H_
