/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

// =====================================================================
// +allocWithZone: / -dealloc interception — Swift facade
//
// Swift entry point over the Obj-C allocation interception (objc_alloc_hook):
// swizzles +[NSObject allocWithZone:] / -[NSObject dealloc] and feeds the
// shared passive memory sampler. Runs alongside SwiftAllocInterception,
// which covers pure-Swift class allocations via swift_allocObject; the two
// paths are disjoint (NSObject-rooted vs pure-Swift), so together they widen
// coverage with no double-counting. See docs/SWIZZLING.md for the
// never-restore / composition rules this path follows.
// =====================================================================

/// Outcome of `ObjCAllocInterception.start()`.
internal enum ObjCAllocHookStatus: Sendable, Equatable {
    case ok
    case alreadyInstalled
    case failedSampler
    case failedNoMethod

    init(_ raw: dd_objc_alloc_hook_status_t) {
        switch raw {
        case DD_OBJC_ALLOC_HOOK_OK: self = .ok
        case DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED: self = .alreadyInstalled
        case DD_OBJC_ALLOC_HOOK_FAILED_SAMPLER: self = .failedSampler
        case DD_OBJC_ALLOC_HOOK_FAILED_NO_METHOD: self = .failedNoMethod
        default: self = .failedNoMethod
        }
    }
}

/// Counters that describe what the swizzle layer itself observed.
internal struct ObjCAllocDiagnostics: Sendable {
    let totalInvocations: UInt64
    let observedAllocations: UInt64
    let skippedDisabled: UInt64
    let totalDeallocInvocations: UInt64
    let observedDeallocations: UInt64
    let skippedDeallocDisabled: UInt64
}

internal enum ObjCAllocInterception {
    static let defaultPoissonRateBytes: UInt64 = UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)

    @discardableResult
    static func start(poissonRateBytes: UInt64 = defaultPoissonRateBytes) -> ObjCAllocHookStatus {
        ObjCAllocHookStatus(dd_objc_alloc_hook_start(poissonRateBytes))
    }

    static func stop() {
        dd_objc_alloc_hook_stop()
    }

    static var isRunning: Bool {
        dd_objc_alloc_hook_is_running()
    }

    static func diagnostics() -> ObjCAllocDiagnostics {
        let raw = dd_objc_alloc_hook_diagnostics()
        return ObjCAllocDiagnostics(
            totalInvocations: raw.total_invocations,
            observedAllocations: raw.observed_allocations,
            skippedDisabled: raw.skipped_disabled,
            totalDeallocInvocations: raw.total_dealloc_invocations,
            observedDeallocations: raw.observed_deallocations,
            skippedDeallocDisabled: raw.skipped_dealloc_disabled
        )
    }
}

#endif // !os(watchOS)
