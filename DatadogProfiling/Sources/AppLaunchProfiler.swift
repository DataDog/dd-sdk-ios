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

internal final class AppLaunchProfiler: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(cmd as AppLaunchProfileStop) = message else {
            return false
        }

        guard ctor_profiler_get_status() == CTOR_PROFILER_STATUS_RUNNING else {
            return false
        }

        ctor_profiler_stop()
        core.set(context: ProfilingContext(status: .current))
        defer { ctor_profiler_destroy() }

        guard let profile = ctor_profiler_get_profile() else {
            return false
        }

        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let size = dd_pprof_serialize(profile, &data)

        guard let data = data else {
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
        }

        return true
    }
}

extension ProfilingContext.Status {
    static var current: Self { .init(ctor_profiler_get_status()) }

    init(_ status: ctor_profiler_status_t) {
        switch status {
        case CTOR_PROFILER_STATUS_NOT_STARTED:
            self = .notStarted
        case CTOR_PROFILER_STATUS_RUNNING:
            self = .running
        case CTOR_PROFILER_STATUS_STOPPED:
            self = .stopped
        case CTOR_PROFILER_STATUS_TIMEOUT:
            self = .timedOut
        case CTOR_PROFILER_STATUS_PREWARMED:
            self = .prewarmed
        case CTOR_PROFILER_STATUS_SAMPLED_OUT:
            self = .sampledOut
        case CTOR_PROFILER_STATUS_ERROR:
            self = .error
        case CTOR_PROFILER_STATUS_ALLOCATION_FAILED:
            self = .error
        case CTOR_PROFILER_STATUS_START_FAILED:
            self = .error
        default:
            self = .notStarted
        }
    }
}
