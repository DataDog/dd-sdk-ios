/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if !os(watchOS)

/// Coordinates profiler ownership and profile sharing across SDK core instances.
internal protocol ProfilerCoordinating: AnyObject {
    /// Registers a profiler and returns its role in shared profiler coordination.
    func register(_ profiler: DatadogProfiler) -> DatadogProfiler.Role
    /// Removes a profiler from shared profiler coordination.
    func unregister(_ profiler: DatadogProfiler)
    /// Returns whether an app-launch profile can be shared with another profiler.
    func canNotifyAppLaunchProfile(from profiler: DatadogProfiler) -> Bool
    /// Shares a profile with the other registered profilers.
    func notify(
        profile: OpaquePointer,
        operation: ProfilingOperation,
        from profiler: DatadogProfiler,
        synchronizedWith queue: DispatchQueue
    )
    /// Clears profiling correlation data from the other registered profilers.
    func cleanUp(profiler: DatadogProfiler, synchronizedWith queue: DispatchQueue)
}

/// Arbitrates native profiler ownership across SDK core instances.
/// Profile lifecycle and observer writes remain owned by `DatadogProfiler`.
internal final class ProfilerCoordinator: ProfilerCoordinating {
    static let shared = ProfilerCoordinator()

    private weak var activeProfiler: DatadogProfiler?
    private let profilers: NSHashTable<DatadogProfiler> = .weakObjects()
    private let lock = NSLock()

    func register(_ profiler: DatadogProfiler) -> DatadogProfiler.Role {
        lock.lock()
        defer { lock.unlock() }

        profilers.add(profiler)

        guard activeProfiler == nil else {
            return .observer
        }

        activeProfiler = profiler
        return .coordinator
    }

    func unregister(_ profiler: DatadogProfiler) {
        lock.lock()
        defer { lock.unlock() }

        profilers.remove(profiler)

        if activeProfiler === profiler {
            activeProfiler = nil
        }
    }

    func canNotifyAppLaunchProfile(from profiler: DatadogProfiler) -> Bool {
        observers(excluding: profiler).contains { $0.canObserveAppLaunchProfile }
    }

    func notify(
        profile: OpaquePointer,
        operation: ProfilingOperation,
        from profiler: DatadogProfiler,
        synchronizedWith queue: DispatchQueue
    ) {
        observers(excluding: profiler).forEach { observer in
            observer.write(
                observedProfile: profile,
                as: operation,
                synchronizedWith: queue
            )
        }
    }

    func cleanUp(profiler: DatadogProfiler, synchronizedWith queue: DispatchQueue) {
        observers(excluding: profiler).forEach { observer in
            observer.cleanUpObservedState(synchronizedWith: queue)
        }
    }

    private func observers(excluding profiler: DatadogProfiler) -> [DatadogProfiler] {
        lock.lock()
        defer { lock.unlock() }

        return profilers.allObjects.filter {
            $0 !== profiler && $0 !== activeProfiler
        }
    }
}

#endif
