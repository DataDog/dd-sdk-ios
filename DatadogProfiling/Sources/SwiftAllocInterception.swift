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

/// Outcome of `SwiftAllocInterception.start()`.
internal enum SwiftAllocHookStatus: Sendable, Equatable {
    case ok
    case alreadyInstalled
    case failedNoSymbol

    init(_ raw: dd_swift_alloc_hook_status_t) {
        switch raw {
        case DD_SWIFT_ALLOC_HOOK_OK: self = .ok
        case DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED: self = .alreadyInstalled
        case DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL: self = .failedNoSymbol
        default: self = .failedNoSymbol
        }
    }
}

/// Counters describing what the pure-Swift interception layer observed.
internal struct SwiftAllocDiagnostics: Sendable {
    let allocInvocations: UInt64
    let deallocInvocations: UInt64
    let deallocObjectInvocations: UInt64
    let reentrantSkips: UInt64
    let allocBound: Bool
    let deallocBound: Bool
}

/// Swift facade over the `swift_allocObject` interception path. Runs alongside
/// `MemorySwizzlingPOC`; the two allocation paths are disjoint (pure-Swift
/// class -> swift_allocObject; NSObject-rooted -> +allocWithZone:).
internal enum SwiftAllocInterception {
    static let defaultPoissonRateBytes: UInt64 = UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)

    @discardableResult
    static func start(poissonRateBytes: UInt64 = defaultPoissonRateBytes) -> SwiftAllocHookStatus {
        SwiftAllocHookStatus(dd_swift_alloc_hook_start(poissonRateBytes))
    }

    static func stop() {
        dd_swift_alloc_hook_stop()
    }

    static var isRunning: Bool {
        // The hook has no dedicated is-running flag; the shared sampler reflects it.
        dd_memory_profiler_is_running()
    }

    static func diagnostics() -> SwiftAllocDiagnostics {
        let raw = dd_swift_alloc_hook_diagnostics()
        return SwiftAllocDiagnostics(
            allocInvocations: raw.alloc_invocations,
            deallocInvocations: raw.dealloc_invocations,
            deallocObjectInvocations: raw.dealloc_object_invocations,
            reentrantSkips: raw.reentrant_skips,
            allocBound: raw.alloc_bound,
            deallocBound: raw.dealloc_bound
        )
    }
}

#endif // !os(watchOS)
