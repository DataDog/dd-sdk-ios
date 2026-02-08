/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class AppLaunchProfiler: FeatureMessageReceiver, ProfilingWriter {
    /// Shared counter to track pending `AppLaunchProfiler`s from handling the `ProfilerStop` message
    private static var pendingInstances: Int = 0
    private static var appLaunchProfile: OpaquePointer?
    private static let lock = NSLock()

    let telemetryController: ProfilingTelemetryController
    let operation: ProfilingOperation = .appLaunch
    private let isContinuousProfiling: Bool

    init(
        isContinuousProfiling: Bool,
        telemetryController: ProfilingTelemetryController = .init()
    ) {
        Self.registerInstance()
        self.isContinuousProfiling = isContinuousProfiling
        self.telemetryController = telemetryController
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(cmd as TTIDMessage) = message else {
            return false
        }

        print("*******************************handling TTID")

        let profileStatus = profiler_get_status()
        guard profileStatus == PROFILER_STATUS_RUNNING
                || profileStatus == PROFILER_STATUS_TIMEOUT
                || profileStatus == PROFILER_STATUS_STOPPED else {
            if profileStatus != PROFILER_STATUS_SAMPLED_OUT
                && profileStatus != PROFILER_STATUS_PREWARMED {
                telemetryController.send(metric: AppLaunchMetric.statusNotHandled)
            }
            return false
        }

        if isContinuousProfiling == false {
            profiler_stop()
        }
        core.set(context: ProfilingContext(status: .current))
        defer { Self.unregisterInstance() }

        guard let profile = appLaunchProfile() else {
            telemetryController.send(metric: AppLaunchMetric.noProfile)
            return false
        }

        self.writeProfilingEvent(with: profile, from: core.scope(for: ProfilerFeature.self))

        return true
    }

    private func appLaunchProfile() -> OpaquePointer? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let profile = Self.appLaunchProfile {
            return profile
        }

        let currentProfile = profiler_get_profile(true)
        Self.appLaunchProfile = currentProfile

        return currentProfile
    }
}

// MARK: - Handle AppLaunchProfiler instances

private extension AppLaunchProfiler {
    /// Registers the `AppLaunchProfiler` to handle the `ProfilerStop` message.
    static func registerInstance() {
        lock.lock()
        defer { lock.unlock() }

        pendingInstances += 1
    }

    /// Decrements the pending instance counter and destroys the profiler when all instances are done.
    static func unregisterInstance() {
        lock.lock()
        defer { lock.unlock() }

        pendingInstances -= 1
    }
}

// MARK: - Testing funcs

extension AppLaunchProfiler {
    /// Returns the current pending instances count.
    static var currentPendingInstances: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingInstances
    }

    /// Resets the pending instances counter.
    static func resetPendingInstances() {
        lock.lock()
        defer { lock.unlock() }
        pendingInstances = 0
    }
}

extension ProfilingContext.Status {
    static var current: Self { .init(profiler_get_status()) }

    init(_ status: profiler_status_t) {
        switch status {
        case PROFILER_STATUS_NOT_STARTED:
            self = .stopped(reason: .notStarted)
        case PROFILER_STATUS_RUNNING:
            self = .running
        case PROFILER_STATUS_STOPPED:
            self = .stopped(reason: .manual)
        case PROFILER_STATUS_TIMEOUT:
            self = .stopped(reason: .timeout)
        case PROFILER_STATUS_PREWARMED:
            self = .stopped(reason: .prewarmed)
        case PROFILER_STATUS_SAMPLED_OUT:
            self = .stopped(reason: .sampledOut)
        case PROFILER_STATUS_ALLOCATION_FAILED:
            self = .error(reason: .memoryAllocationFailed)
        case PROFILER_STATUS_ALREADY_STARTED:
            self = .error(reason: .alreadyStarted)
        default:
            self = .unknown
        }
    }
}
