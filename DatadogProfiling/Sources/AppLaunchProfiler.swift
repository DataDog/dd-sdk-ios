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

internal final class AppLaunchProfiler: FeatureMessageReceiver {
    private static let pendingInstances = PendingInstancesHandler()

    private let telemetryController: ProfilingTelemetryController

    init(telemetryController: ProfilingTelemetryController = .init()) {
        Self.registerInstance()
        self.telemetryController = telemetryController
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(cmd as ProfilerStop) = message else {
            return false
        }

        let profileStatus = dd_profiler_get_status()
        guard profileStatus == DD_PROFILER_STATUS_RUNNING
                || profileStatus == DD_PROFILER_STATUS_TIMEOUT
                || profileStatus == DD_PROFILER_STATUS_STOPPED else {
            if profileStatus != DD_PROFILER_STATUS_SAMPLED_OUT
                && profileStatus != DD_PROFILER_STATUS_PREWARMED {
                telemetryController.send(metric: AppLaunchMetric.statusNotHandled)
            }
            return false
        }

        dd_profiler_stop()
        core.set(context: ProfilingContext(status: .current))
        defer { Self.unregisterInstance() }

        guard let profile = dd_profiler_get_profile() else {
            telemetryController.send(metric: AppLaunchMetric.noProfile)
            return false
        }

        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let duration = (end - start).dd.toInt64Nanoseconds
        let size = dd_pprof_serialize(profile, &data)

        guard let data else {
            telemetryController.send(metric: AppLaunchMetric.noData)
            return false
        }

        let pprof = Data(bytes: data, count: size)
        dd_pprof_free_serialized_data(data)

        core.scope(for: ProfilerFeature.self).eventWriteContext { context, writer in
            let event = ProfileEvent(
                family: "ios",
                runtime: "ios",
                version: "4",
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end),
                attachments: [ProfileEvent.Constants.wallFilename],
                tags: [
                    "service:\(context.service)",
                    "version:\(context.version)",
                    "sdk_version:\(context.sdkVersion)",
                    "profiler_version:\(context.sdkVersion)",
                    "runtime_version:\(context.os.version)",
                    "env:\(context.env)",
                    "source:\(context.source)",
                    "language:swift",
                    "format:pprof",
                    "remote_symbols:yes",
                    "operation:launch"
                ].joined(separator: ","),
                additionalAttributes: cmd.context
            )

            writer.write(value: pprof, metadata: event)
            self.telemetryController.send(metric: AppLaunchMetric(status: .init(profileStatus), durationNs: duration, fileSize: Int64(size)))
        }

        return true
    }
}

// MARK: - Handle AppLaunchProfiler instances

private extension AppLaunchProfiler {
    /// Registers the `AppLaunchProfiler` to handle the `ProfilerStop` message.
    static func registerInstance() {
        pendingInstances.increment()
    }

    /// Decrements the pending instance counter and destroys the profiler when all instances are done.
    static func unregisterInstance() {
        if pendingInstances.decrement() <= 0 {
            dd_profiler_destroy()
        }
    }
}

// MARK: - Testing funcs

extension AppLaunchProfiler {
    /// Returns the current pending instances count.
    static var currentPendingInstances: Int {
        pendingInstances.current()
    }

    /// Resets the pending instances counter.
    static func resetPendingInstances() {
        pendingInstances.reset()
    }
}

// MARK: - ProfilingContext Status

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
        case DD_PROFILER_STATUS_SAMPLED_OUT:
            self = .stopped(reason: .sampledOut)
        case DD_PROFILER_STATUS_ALLOCATION_FAILED:
            self = .error(reason: .memoryAllocationFailed)
        case DD_PROFILER_STATUS_ALREADY_STARTED:
            self = .error(reason: .alreadyStarted)
        default:
            self = .unknown
        }
    }
}

// MARK: - PendingInstances handler

private final class PendingInstancesHandler: @unchecked Sendable {
    private var counter: Int = 0
    private let lock = NSLock()

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
    }

    func decrement() -> Int {
        lock.lock()
        defer { lock.unlock() }
        counter -= 1
        return counter
    }

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counter
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        counter = 0
    }
}
#endif
