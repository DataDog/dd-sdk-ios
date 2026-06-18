/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_SWIZZLE_POC_H_
#define DD_MEMORY_SWIZZLE_POC_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================
// +allocWithZone: Swizzling Spike (follow-up to RUM-16460)
//
// Pre-RFC spike that validates whether swizzling +allocWithZone: on
// NSObject is a viable App Store-safe interception primitive for the
// memory profiler. The RUM-16460 POC proved malloc_zone hooks are
// bypassed by libmalloc's fast path; this spike answers whether the
// Obj-C runtime path is reachable instead.
//
// Findings document target:
// Simao's Brain/my-wiki/wiki/projects/profiling/memory/spike-allocwithzone-findings.md
// =====================================================================

/**
 * Status returned by dd_memory_swizzle_start.
 */
typedef enum {
    /// Swizzle is in place; observation pipeline is active.
    DD_MEMORY_SWIZZLE_STATUS_OK = 0,
    /// Swizzle was already installed by a prior call.
    DD_MEMORY_SWIZZLE_STATUS_ALREADY_INSTALLED = 1,
    /// The passive sampler could not be started (sample table allocation failed).
    DD_MEMORY_SWIZZLE_STATUS_FAILED_SAMPLER = 2,
    /// NSObject's +allocWithZone: class method could not be resolved.
    DD_MEMORY_SWIZZLE_STATUS_FAILED_NO_METHOD = 3
} dd_memory_swizzle_status_t;

/**
 * Diagnostics for the swizzle layer itself (separate from the sampler counters
 * in dd_memory_profiler_diagnostics).
 */
typedef struct dd_memory_swizzle_diagnostics {
    /// Total times the swizzled +allocWithZone: was invoked.
    uint64_t total_invocations;
    /// Allocations forwarded to the observer (passed the enabled check).
    uint64_t observed_allocations;
    /// Invocations skipped because the swizzle had been stopped between
    /// the install and the call.
    uint64_t skipped_disabled;
} dd_memory_swizzle_diagnostics_t;

/**
 * Installs the +allocWithZone: swizzle on NSObject and starts the passive
 * sampler. Subsequent Obj-C/Swift class allocations that route through
 * +allocWithZone: will be observed by the Poisson sampler.
 *
 * @param poisson_rate_bytes Mean bytes between samples for the underlying
 *                           sampler. Pass 0 for default (512 KB).
 * @return Install status; OK only on a freshly-started session.
 */
dd_memory_swizzle_status_t dd_memory_swizzle_start(uint64_t poisson_rate_bytes);

/**
 * Restores NSObject's original +allocWithZone: implementation and disables
 * the sampler. Safe to call multiple times.
 */
void dd_memory_swizzle_stop(void);

/**
 * Returns true when the swizzle is installed and observing allocations.
 */
bool dd_memory_swizzle_is_running(void);

/**
 * Returns a copy of the swizzle-layer counters.
 */
dd_memory_swizzle_diagnostics_t dd_memory_swizzle_diagnostics(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_MEMORY_SWIZZLE_POC_H_
