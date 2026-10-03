/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_LIVE_SET_TESTING_H_
#define DD_MEMORY_LIVE_SET_TESTING_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include "memory_live_set.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Hash bucket for constructing deterministic collision and saturation fixtures.
size_t dd_memory_live_set_bucket(const void *address);

/// Reports visited address-index entries through the real removal algorithm.
/// Probe measurement is compiled out of the production removal path.
bool dd_memory_live_set_remove_with_probe_length_for_testing(
    dd_memory_live_set_t *table, uint64_t generation, const void *address,
    size_t *probe_length);

/// Injects an accounting mismatch to check snapshot bounds and rejection.
void dd_memory_live_set_override_occupancy_for_testing(
    dd_memory_live_set_t *table, uint64_t value);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_MEMORY_LIVE_SET_TESTING_H_
