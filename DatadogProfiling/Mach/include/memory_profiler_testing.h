/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_MEMORY_PROFILER_TESTING_H_
#define DD_MEMORY_PROFILER_TESTING_H_

#include "memory_profiler.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================
// Test-only API for the Memory Profiler RFC implementation (RUM-16460).
// Lets tests inspect internal state and probe failure modes that aren't
// reachable through the production C API.
// =====================================================================

/**
 * Probes whether the default malloc zone struct lives on a writable page
 * without actually installing hooks.
 *
 * @return true if direct function pointer replacement would succeed,
 *         false if the page is read-only (mprotect would be required).
 */
bool dd_memory_test_default_zone_writable(void);

/**
 * Resets all profiler state to uninitialized.
 *
 * Drops all sampled allocations, zeros diagnostics, and unsets the
 * enabled flag without uninstalling hooks (hook function pointers
 * remain installed but short-circuit to the original implementations).
 *
 * Used by tests to start each scenario with a clean baseline.
 */
void dd_memory_test_reset(void);

/**
 * Forces the next allocation to be sampled regardless of the Poisson
 * counter state.
 *
 * Used by tests to deterministically exercise the sampling path without
 * needing to allocate hundreds of KB to trip the counter.
 */
void dd_memory_test_force_next_sample(void);

/**
 * Returns the count of allocations sampled since the last reset.
 */
uint64_t dd_memory_test_sampled_count(void);

/**
 * Returns the count of currently live sampled allocations
 * (sampled and not yet freed).
 */
uint64_t dd_memory_test_live_count(void);

/**
 * Returns the active profiler session generation.
 *
 * Tests use this token to prove that table work captured before a restart
 * cannot be published into the new session.
 */
uint64_t dd_memory_test_session_generation(void);

/**
 * Returns the table bucket selected for an address.
 *
 * Lets collision tests follow the production hash without duplicating its
 * implementation.
 */
size_t dd_memory_test_bucket_for(const void* ptr);

/**
 * Inserts a deterministic sample directly into the live table.
 *
 * This bypasses Poisson selection and backtrace capture while preserving
 * production insertion, capacity, diagnostics, and session validation.
 *
 * @return true if inserted; false for a stale session, duplicate, or full table.
 */
bool dd_memory_test_insert_sample(
    const void* ptr,
    uint64_t size,
    uint64_t session_generation
);

/**
 * Returns the recorded source for a live sampled address, or
 * DD_MEMORY_SOURCE_ZONE if the address is not in the live table.
 */
dd_memory_source_t dd_memory_test_sample_source(const void* ptr);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_MEMORY_PROFILER_TESTING_H_
