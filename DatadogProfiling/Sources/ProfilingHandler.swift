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
    var attributes: [AttributeKey: AttributeValue] { get }
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

        if let hangs {
            attributes[RUMCoreContext.IDs.errorID] = hangs.map { $0.id }
        }

        if let longTasks {
            attributes[RUMCoreContext.IDs.longTaskID] = longTasks.map { $0.id }
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
        attributes: [AttributeKey: AttributeValue]
    ) {
        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
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
                family: Constants.family,
                runtime: Constants.runtime,
                version: Constants.version,
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end),
                attachments: [
                    ProfileAttachments.Constants.wallFilename,
                    ProfileAttachments.Constants.rumEventsFilename
                ],
                tags: [
                    tag(Tag.Key.service, context.service),
                    tag(Tag.Key.version, context.version),
                    tag(Tag.Key.sdkVersion, context.sdkVersion),
                    tag(Tag.Key.profilerVersion, context.sdkVersion),
                    tag(Tag.Key.runtimeVersion, context.os.version),
                    tag(Tag.Key.env, context.env),
                    tag(Tag.Key.source, context.source),
                    tag(Tag.Key.language, Tag.Value.language),
                    tag(Tag.Key.format, Tag.Value.format),
                    tag(Tag.Key.remoteSymbols, Tag.Value.remoteSymbols),
                    tag(Tag.Key.operation, operation.rawValue)
                ].joined(separator: ","),
                additionalAttributes: attributes
            )

            let rumEventsData = try? encoder.encode(rumEvents)
            let attachments = ProfileAttachments(pprof: pprof, rumEvents: rumEventsData)
            writer.write(value: event, metadata: attachments)
        }
    }

    private func tag(_ key: String, _ value: String) -> String {
        "\(key):\(value)"
    }
}

private enum Constants {
    static let family = "ios"
    static let runtime = "ios"
    static let version = "4"
}

private enum Tag {
    enum Key {
        static let service = "service"
        static let version = "version"
        static let sdkVersion = "sdk_version"
        static let profilerVersion = "profiler_version"
        static let runtimeVersion = "runtime_version"
        static let env = "env"
        static let source = "source"
        static let language = "language"
        static let format = "format"
        static let remoteSymbols = "remote_symbols"
        static let operation = "operation"
    }

    enum Value {
        static let language = "swift"
        static let format = "pprof"
        static let remoteSymbols = "yes"
    }
}
