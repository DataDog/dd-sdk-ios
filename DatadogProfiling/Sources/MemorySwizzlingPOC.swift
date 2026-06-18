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
// +allocWithZone: Swizzling Spike — Swift facade
//
// Validates whether method swizzling on NSObject is a viable interception
// primitive for the iOS memory profiler. Pivot from the malloc_zone
// approach of RUM-16460, which was App Store safe but bypassed by
// libmalloc's fast path.
//
// NOT FOR PRODUCTION. This is a pre-RFC spike to answer five questions:
//   Q1: does the swizzle fire for typical Obj-C/Swift allocation patterns?
//   Q2: what allocation patterns bypass the swizzle?
//   Q3: what is the measured overhead vs unswizzled baseline?
//   Q4: does the reentrancy guard hold under concurrent stress?
//   Q7: are class name and instance size extractable at the swizzle point?
// =====================================================================

/// Outcome of `MemorySwizzlingPOC.start()`.
internal enum MemorySwizzleStatus: Sendable, Equatable {
    case ok
    case alreadyInstalled
    case failedSampler
    case failedNoMethod

    init(_ raw: dd_memory_swizzle_status_t) {
        switch raw {
        case DD_MEMORY_SWIZZLE_STATUS_OK: self = .ok
        case DD_MEMORY_SWIZZLE_STATUS_ALREADY_INSTALLED: self = .alreadyInstalled
        case DD_MEMORY_SWIZZLE_STATUS_FAILED_SAMPLER: self = .failedSampler
        case DD_MEMORY_SWIZZLE_STATUS_FAILED_NO_METHOD: self = .failedNoMethod
        default: self = .failedNoMethod
        }
    }
}

/// Counters that describe what the swizzle layer itself observed.
internal struct MemorySwizzleDiagnostics: Sendable {
    let totalInvocations: UInt64
    let observedAllocations: UInt64
    let skippedDisabled: UInt64
}

internal enum MemorySwizzlingPOC {
    static let defaultPoissonRateBytes: UInt64 = UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)

    @discardableResult
    static func start(poissonRateBytes: UInt64 = defaultPoissonRateBytes) -> MemorySwizzleStatus {
        MemorySwizzleStatus(dd_memory_swizzle_start(poissonRateBytes))
    }

    static func stop() {
        dd_memory_swizzle_stop()
    }

    static var isRunning: Bool {
        dd_memory_swizzle_is_running()
    }

    static func diagnostics() -> MemorySwizzleDiagnostics {
        let raw = dd_memory_swizzle_diagnostics()
        return MemorySwizzleDiagnostics(
            totalInvocations: raw.total_invocations,
            observedAllocations: raw.observed_allocations,
            skippedDisabled: raw.skipped_disabled
        )
    }
}

#endif // !os(watchOS)
