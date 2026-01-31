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

internal final class ContinuousProfiler {
    /// Shared counter to track pending `AppLaunchProfiler`s from handling the `ProfilerStop` message
    private static var pendingInstances: Int = 0
    private static let lock = NSLock()

    private let telemetryController: ProfilingTelemetryController

    private var timer: Timer?

    init(
        core: DatadogCoreProtocol,
        telemetryController: ProfilingTelemetryController = .init(),
        frequency: TimeInterval = TimeInterval(10)
    ) {
        Self.registerInstance()
        self.telemetryController = telemetryController

        print("*******************************init continuous profiling \(Date())")

        // Schedule reoccurring samples
        let timer = Timer(
            timeInterval: frequency,
            repeats: true
        ) { [weak self] _ in

            self?.sendProfile(core: core)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        Self.unregisterInstance()
    }

    func sendProfile(core: DatadogCoreProtocol) {
        print("*******************************handling continuous profiling \(Date())")

        let profileStatus = ctor_profiler_get_status()
        guard profileStatus == CTOR_PROFILER_STATUS_RUNNING else {
            print("+++++++++++++++profiling status\(profileStatus)")
            return
        }

        core.set(context: ProfilingContext(status: .current))

        guard let profile = ctor_profiler_get_profile(true) else {

            print("+++++++++++++++no profile")
            return
        }

        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let duration = (end - start).dd.toInt64Nanoseconds
        let size = dd_pprof_serialize(profile, &data)

        guard let data else {
            return
        }

        print("+++++++++++++++\(duration) ++++++++ \(size)")

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
                    "operation:continuous_profiling"
                ].joined(separator: ","),
                additionalAttributes: [:]
            )

            print("*******************************Writing continuous profile")

            writer.write(value: pprof, metadata: event)
        }
    }
}

// MARK: - Handle AppLaunchProfiler instances

private extension ContinuousProfiler {
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
        if pendingInstances <= 0 {
            ctor_profiler_destroy()
        }
    }
}

// MARK: - Testing funcs

extension ContinuousProfiler {
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
