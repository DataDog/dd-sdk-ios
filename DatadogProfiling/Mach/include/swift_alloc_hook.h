/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_SWIFT_ALLOC_HOOK_H_
#define DD_SWIFT_ALLOC_HOOK_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stdint.h>

#include "memory_profiler.h"

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================
// swift_allocObject interception spike (RUM-16460 follow-up)
//
// Validates whether pure-Swift class allocations — which bypass the
// Obj-C +allocWithZone: swizzle because they go through the Swift
// runtime allocator, not the Obj-C runtime — can be intercepted in an
// App Store-safe way via symbol rebinding (fishhook) of
// `swift_allocObject` / `swift_deallocClassInstance`.
//
// This is a validation spike, not the production interceptor. It runs
// ALONGSIDE the +allocWithZone: swizzle; the two allocation paths are
// disjoint (pure-Swift class -> swift_allocObject; NSObject-rooted ->
// objc_allocWithZone), so together they widen coverage with no
// double-counting.
// =====================================================================

typedef enum {
    /// Rebinding installed and enabled.
    DD_SWIFT_ALLOC_HOOK_OK = 0,
    /// A prior call already installed the rebinding; observation re-enabled.
    DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED = 1,
    /// The Swift runtime allocator symbol could not be resolved.
    DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL = 2
} dd_swift_alloc_hook_status_t;

typedef struct dd_swift_alloc_hook_diagnostics {
    /// Times the swift_allocObject trampoline was invoked while enabled.
    uint64_t alloc_invocations;
    /// Times the swift_deallocClassInstance trampoline was invoked while enabled.
    uint64_t dealloc_invocations;
    /// Times the swift_deallocObject trampoline was invoked while enabled.
    uint64_t dealloc_object_invocations;
    /// Trampoline entries skipped because of the reentrancy guard.
    uint64_t reentrant_skips;
    /// True once the alloc symbol was resolved and at least one slot rebound.
    bool alloc_bound;
    /// True once the dealloc symbol was resolved and at least one slot rebound.
    bool dealloc_bound;
} dd_swift_alloc_hook_diagnostics_t;

/// Install the rebinding (idempotent), bring up the shared passive sampler, and
/// enable observation. Pass DD_MEMORY_POISSON_DEFAULT_RATE_BYTES for the default.
dd_swift_alloc_hook_status_t dd_swift_alloc_hook_start(uint64_t poisson_rate_bytes);

/// Disable observation. Follows the never-restore discipline: the trampolines
/// stay installed and keep forwarding, they simply stop recording.
void dd_swift_alloc_hook_stop(void);

dd_swift_alloc_hook_diagnostics_t dd_swift_alloc_hook_diagnostics(void);

// ---- Testing helpers (spike questions SQ1..SQ3) ---------------------

/// Reset counters and any armed capture. Does not uninstall the rebinding.
void dd_swift_alloc_test_reset(void);

/// Arm a one-shot capture of the NEXT observed allocation's metadata + size,
/// on the calling thread. Deterministic for single-object test cases.
void dd_swift_alloc_test_arm_capture(void);

/// Instance size (bytes) of the captured allocation, or 0 if none captured.
uint64_t dd_swift_alloc_test_captured_size(void);

/// Copy the captured allocation's demangled Swift type name into `buf`
/// (NUL-terminated, up to `buf_len`). Resolved off the hot path via
/// swift_getTypeName. Returns the number of bytes written (excluding NUL).
uint64_t dd_swift_alloc_test_captured_name(char *buf, uint64_t buf_len);

// ---- Free-side / live-set validation (SQ4) --------------------------
//
// To keep the live set deterministic (the hook is process-wide and sees
// every pure-Swift allocation), the test registers the *type metadata* of
// the fixture classes it cares about. Only allocations whose metadata is
// registered are inserted into the spike live set; deallocations remove by
// address. `metadata` is a Swift class metatype reinterpreted as a pointer
// (e.g. `unsafeBitCast(MyClass.self, to: UnsafeMutableRawPointer.self)`).

/// Register a fixture class metadata pointer for live-set tracking.
void dd_swift_alloc_test_register_class(void *metadata);

/// Number of tracked (registered-class) objects currently live.
uint64_t dd_swift_alloc_test_live_count(void);

/// Whether a specific object address is currently in the tracked live set.
bool dd_swift_alloc_test_is_live(void *address);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_SWIFT_ALLOC_HOOK_H_
