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

protocol ProfilingWriter {
    var telemetryController: ProfilingTelemetryController { get }
    var operation: ProfilingOperation { get }
}

extension ProfilingWriter {
    func writeProfilingEvent(with profile: OpaquePointer?, from featureScope: FeatureScope) {
        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let duration = (end - start).dd.toInt64Nanoseconds
        let size = dd_pprof_serialize(profile, &data)

        guard let data else {
            telemetryController.send(metric: AppLaunchMetric.noData)
            return
        }

        print("+++++++++++++++\(end - start) ++++++++ \(size)")

        let pprof = Data(bytes: data, count: size)
        dd_pprof_free_serialized_data(data)

        featureScope.eventWriteContext { context, writer in
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
                    "operation:\(operation.rawValue)"
                ].joined(separator: ","),
                additionalAttributes: [:]
            )

            print("*******************************Writing profile")
            
            writer.write(value: pprof, metadata: event)
            //telemetryController.send(metric: AppLaunchMetric(status: .init(profileStatus), durationNs: duration, fileSize: Int64(size)))
        }
    }
}
