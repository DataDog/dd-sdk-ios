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

internal protocol ProfilingHandler {
    var attributes: [String: AttributeValue] { get }
    var operation: ProfilingOperation { get }

    var featureScope: FeatureScope { get }
    var telemetryController: ProfilingTelemetryController { get }
    var encoder: JSONEncoder { get }
}

extension ProfilingHandler {
    @discardableResult
    func updateProfilingContext() -> ProfilingContext {
        let profilingContext = ProfilingContext(status: .current)
        self.featureScope.set(context: profilingContext)

        return profilingContext
    }

    func write(
        profile: OpaquePointer,
        rumVitals: [Vital],
        hangs: [DurationEvent]? = nil,
        longTasks: [DurationEvent]? = nil
    ) {
        var attributes = self.attributes

        if rumVitals.isEmpty == false {
            attributes[RUMCoreContext.IDs.vitalID] = rumVitals.map { $0.id }
            attributes[RUMCoreContext.IDs.vitalLabel] = rumVitals.map { $0.name }
        }

        self.writeProfilingEvent(
            with: profile,
            rumEvents: RUMEvents(vitals: rumVitals, hangs: hangs, longTasks: longTasks),
            attributes: attributes
        )
    }

    private func writeProfilingEvent(
        with profile: OpaquePointer,
        rumEvents: RUMEvents,
        attributes: [String: AttributeValue]
    ) {
        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let duration = (end - start).dd.toInt64Nanoseconds
        let size = dd_pprof_serialize(profile, &data)

        guard let data else {
            // RUM-14251: Add telemetry for custom and continuous profiling
            telemetryController.send(metric: AppLaunchMetric.noData)
            return
        }

        let pprof = Data(bytes: data, count: size)
        dd_pprof_free_serialized_data(data)

        featureScope.eventWriteContext { context, writer in
            let event = ProfileEvent(
                family: "ios",
                runtime: "ios",
                version: "4",
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end),
                attachments: [
                    ProfileAttachments.Constants.wallFilename,
                    ProfileAttachments.Constants.rumEventsFilename
                ],
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
                additionalAttributes: attributes
            )

            let rumEventsData = try? encoder.encode(rumEvents)
            let attachments = ProfileAttachments(pprof: pprof, rumEvents: rumEventsData)
            writer.write(value: event, metadata: attachments)
        }
    }
}
