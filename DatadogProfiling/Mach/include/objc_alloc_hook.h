/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_OBJC_ALLOC_HOOK_H_
#define DD_OBJC_ALLOC_HOOK_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================
// +allocWithZone: / -dealloc Obj-C allocation interception (RUM-16460)
//
// Intercepts NSObject-rooted allocations by swizzling +allocWithZone: and
// -dealloc on NSObject and reporting them to the passive memory sampler.
// Complements the swift_allocObject rebinding (swift_alloc_hook), which
// covers pure-Swift class allocations. See docs/SWIZZLING.md for the
// never-restore / composition discipline this path follows.
// =====================================================================

/**
 * Status returned by dd_objc_alloc_hook_start.
 */
typedef enum {
    /// Swizzle is in place; observation pipeline is active.
    DD_OBJC_ALLOC_HOOK_OK = 0,
    /// Swizzle was already installed by a prior call.
    DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED = 1,
    /// The passive sampler could not be started (sample table allocation failed).
    DD_OBJC_ALLOC_HOOK_FAILED_SAMPLER = 2,
    /// NSObject's +allocWithZone: class method could not be resolved.
    DD_OBJC_ALLOC_HOOK_FAILED_NO_METHOD = 3
} dd_objc_alloc_hook_status_t;

/**
 * Diagnostics for the swizzle layer itself (separate from the sampler counters
 * in dd_memory_profiler_diagnostics).
 */
typedef struct dd_objc_alloc_hook_diagnostics {
    /// Total times the swizzled +allocWithZone: was invoked.
    uint64_t total_invocations;
    /// Allocations forwarded to the observer (passed the enabled check).
    uint64_t observed_allocations;
    /// Invocations skipped because the swizzle had been stopped between
    /// the install and the call.
    uint64_t skipped_disabled;
    /// Total times the swizzled -dealloc was invoked.
    uint64_t total_dealloc_invocations;
    /// Deallocations forwarded to the live-sample observer.
    uint64_t observed_deallocations;
    /// Deallocations skipped because the swizzle was stopped.
    uint64_t skipped_dealloc_disabled;
} dd_objc_alloc_hook_diagnostics_t;

/**
 * Installs +allocWithZone: and -dealloc swizzles on NSObject and starts the
 * passive sampler. Subsequent Obj-C/Swift class allocations that route through
 * +allocWithZone: are observed by the Poisson sampler, and sampled instances
 * are removed from the live set when they reach NSObject's -dealloc.
 *
 * @param poisson_rate_bytes Mean bytes between samples for the underlying
 *                           sampler. Pass 0 for default (512 KB).
 * @return Install status; OK only on a freshly-started session.
 */
dd_objc_alloc_hook_status_t dd_objc_alloc_hook_start(uint64_t poisson_rate_bytes);

/**
 * Stops observing allocations and deallocations and disables the sampler.
 *
 * Follows a never-restore discipline: the installed +allocWithZone: / -dealloc
 * trampolines stay in place and keep forwarding to the implementation captured
 * at install time; only observation is disabled. Restoring the original IMP is
 * intentionally avoided because it cannot compose safely with third-party
 * swizzles on these selectors (see docs/SWIZZLING.md). Safe to call multiple
 * times; a subsequent dd_objc_alloc_hook_start re-enables observation without
 * reinstalling.
 */
void dd_objc_alloc_hook_stop(void);

/**
 * Returns true when the swizzles are installed and observing allocations and
 * deallocations.
 */
bool dd_objc_alloc_hook_is_running(void);

/**
 * Returns a copy of the swizzle-layer counters.
 */
dd_objc_alloc_hook_diagnostics_t dd_objc_alloc_hook_diagnostics(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_OBJC_ALLOC_HOOK_H_
