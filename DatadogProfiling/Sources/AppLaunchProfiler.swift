/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class AppLaunchProfiler: ProfilingHandler {
    /// Shared counter to track pending `AppLaunchProfiler`s until a `TTIDMessage` harvest completes.
    private static var pendingInstances: Int = 0
    /// App launch profile attached with TTID.
    private static var appLaunchProfile: OpaquePointer?
    private static let lock = NSLock()

    private let profilingSamplerProvider: ProfilingSamplerProvider

    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let operation: ProfilingOperation = .appLaunch
    let encoder: JSONEncoder

    @ReadWriteLock
    private(set) var attributes: [AttributeKey: AttributeValue] = [:]
    @ReadWriteLock
    private var currentRUMVitals: [String: Vital] = [:]
    @ReadWriteLock
    private var hasProcessedAppLaunch: Bool = false

    init(
        core: DatadogCoreProtocol,
        profilingSamplerProvider: ProfilingSamplerProvider,
        telemetryController: ProfilingTelemetryController = .init(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        Self.registerInstance()

        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.profilingSamplerProvider = profilingSamplerProvider
        self.telemetryController = telemetryController
        self.encoder = encoder
    }

    deinit {
        if !hasProcessedAppLaunch {
            Self.unregisterInstance()
        }
    }
}

extension AppLaunchProfiler: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard hasProcessedAppLaunch == false else {
            return false
        }

        if case let .payload(message as TTIDMessage) = message {
            hasProcessedAppLaunch = true
            attributes = message.attributes

            if profilingSamplerProvider.isContinuousProfilingConfigured == false
                && self.currentRUMVitals.didCompleteOperations() {
                dd_profiler_stop()
                self.updateProfilingContext()
            }

            _currentRUMVitals.mutate { $0[message.ttid.key] = message.ttid }

            defer { Self.unregisterInstance() }
            guard let profile = appLaunchProfile() else {
                telemetryController.send(metric: AppLaunchMetric.noProfile)
                return false
            }

            self.write(profile: profile, rumVitals: Array(self.currentRUMVitals.values))
            return false
        } else if case let .payload(message as OperationMessage) = message {
            if message.operation.stepType == .start {
                _currentRUMVitals.mutate { $0[message.operation.key] = message.operation }
            } else if var startVital = currentRUMVitals[message.operation.key] {
                _currentRUMVitals.mutate {
                    let duration = message.operation.date.timeIntervalSince(startVital.date)
                    startVital.duration = duration.dd.toInt64Nanoseconds
                    $0[message.operation.key] = startVital
                }
            }
            return false
        }

        return false
    }

    private func appLaunchProfile() -> OpaquePointer? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let profile = Self.appLaunchProfile {
            return profile
        }

        let currentProfile = dd_profiler_flush_and_get_profile()
        Self.appLaunchProfile = currentProfile

        return currentProfile
    }
}

// MARK: - Handle AppLaunchProfiler instances

private extension AppLaunchProfiler {
    /// Registers the `AppLaunchProfiler` for app launch profile lifecycle tracking.
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
        if pendingInstances <= 0 {
            dd_pprof_destroy(Self.appLaunchProfile)
            Self.appLaunchProfile = nil
        }
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

    /// Resets the pending instances counter and destroys any stored profile (for testing).
    static func resetPendingInstances() {
        lock.lock()
        defer { lock.unlock() }
        dd_pprof_destroy(Self.appLaunchProfile)
        Self.appLaunchProfile = nil
        pendingInstances = 0
    }
}

extension ProfilingContext.Status {
    static var current: Self { .init(dd_profiler_get_status()) }

    init(_ status: dd_profiler_status_t) {
        switch status {
        case DD_PROFILER_STATUS_NOT_STARTED:
            self = .stopped(reason: .notStarted)
        case DD_PROFILER_STATUS_RUNNING:
            self = .running
        case DD_PROFILER_STATUS_STOPPED:
            self = .stopped(reason: .manual)
        case DD_PROFILER_STATUS_TIMEOUT:
            self = .stopped(reason: .timeout)
        case DD_PROFILER_STATUS_PREWARMED:
            self = .stopped(reason: .prewarmed)
        case DD_PROFILER_STATUS_ALLOCATION_FAILED:
            self = .error(reason: .memoryAllocationFailed)
        case DD_PROFILER_STATUS_ALREADY_STARTED:
            self = .error(reason: .alreadyStarted)
        default:
            self = .unknown
        }
    }
}

extension Dictionary where Key == String, Value == Vital {
    func didCompleteOperations() -> Bool {
        let vitals = self.values
        return vitals.contains { $0.duration == nil } == false
    }

    func ongoingOperations() -> [String: Vital] {
        filter { $0.1.duration == nil }
    }
}
#endif
