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

internal protocol ProfilingHandler {
    var attributes: [AttributeKey: AttributeValue] { get }
    var currentServerTimeOffset: TimeInterval { get }

    var featureScope: FeatureScope { get }
    var telemetryController: ProfilingTelemetryController { get }
    var encoder: JSONEncoder { get }
}

extension ProfilingHandler {
    @discardableResult
    func updateProfilingContext(
        status: ProfilingContext.Status = .current,
        quotaReason: DDProfiling.QuotaReason? = nil
    ) -> ProfilingContext {
        let profilingContext = ProfilingContext(status: status, quotaReason: quotaReason)
        self.featureScope.set(context: profilingContext)

        return profilingContext
    }

    func write(
        profile: OpaquePointer,
        operation: ProfilingOperation,
        rumVitals: [Vital],
        hangs: [DurationEvent]? = nil,
        longTasks: [DurationEvent]? = nil,
        captureHeapProfile: Bool = false
    ) {
        var attributes = self.attributes

        if rumVitals.isEmpty == false {
            attributes[RUMCoreContext.IDs.vitalID] = rumVitals.map(\.id)
            attributes[RUMCoreContext.IDs.vitalLabel] = rumVitals.map(\.name)
        }

        if let hangs {
            attributes[RUMCoreContext.IDs.errorID] = hangs.map { $0.id }
        }

        if let longTasks {
            attributes[RUMCoreContext.IDs.longTaskID] = longTasks.map { $0.id }
        }

        let rumEvents: [RUMEvent] = rumVitals.map(RUMEvent.vital)
        + (hangs?.map(RUMEvent.hang) ?? [])
        + (longTasks?.map(RUMEvent.longTask) ?? [])

        // When memory profiling is enabled, capture the live-heap snapshot and bundle it as a
        // `heap.pprof` attachment on this same profile event. Go-aligned model: one event carries
        // multiple pprof attachments (wall/CPU + heap) that the backend merges into a single
        // profile, so wall/CPU and memory appear together in the UI instead of as two profiles.
        let heapPprof = captureHeapProfile ? captureHeapPprof(attributes: attributes) : nil

        self.writeProfilingEvent(
            with: profile,
            operation: operation,
            rumEvents: rumEvents,
            attributes: attributes,
            heapPprof: heapPprof
        )
    }

    private func writeProfilingEvent(
        with profile: OpaquePointer,
        operation: ProfilingOperation,
        rumEvents: [RUMEvent],
        attributes: [AttributeKey: AttributeValue],
        heapPprof: Data?
    ) {
        let timeOffsetInNanoseconds = currentServerTimeOffset.dd.toInt64Nanoseconds
        dd_pprof_set_server_time_offset_ns(profile, timeOffsetInNanoseconds)

        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let durationNs = (end - start).dd.toInt64Nanoseconds
        let size = dd_pprof_serialize(profile, &data)

        guard let data else {
            telemetryController.sendNoData(durationNs: durationNs, for: operation)
            return
        }

        let serializedProfileSize = Int(clamping: size)
        guard serializedProfileSize <= Int(ProfilerFeature.Constants.maxObjectSize) else {
            dd_pprof_free_serialized_data(data)
            telemetryController.sendProfileDropped(for: operation, reason: .profileTooLarge)
            return
        }

        let pprof = Data(bytes: data, count: serializedProfileSize)
        dd_pprof_free_serialized_data(data)

        featureScope.eventWriteContext { context, writer in
            var attachmentFilenames = [
                ProfileAttachments.Constants.pprofFilename,
                ProfileAttachments.Constants.rumEventsFilename
            ]
            // Declare the heap attachment only when a snapshot was captured this period.
            if heapPprof != nil {
                attachmentFilenames.append(ProfileAttachments.Constants.heapFilename)
            }

            let event = ProfileEvent(
                family: Constants.family,
                runtime: Constants.runtime,
                version: Constants.version,
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end),
                attachments: attachmentFilenames,
                tags: self.profileTags(context: context, operation: operation),
                additionalAttributes: attributes
            )

            let rumEventsData = try? encoder.encode(rumEvents)
            let attachments = ProfileAttachments(pprof: pprof, rumEvents: rumEventsData, heapPprof: heapPprof)
            writer.write(value: event, metadata: attachments)
            self.telemetryController.sendProfile(
                durationNs: durationNs,
                fileSize: Int64(clamping: size),
                for: operation
            )
        }
    }

    /// Captures a live-heap snapshot on the profiling queue and serializes it to `heap.pprof`
    /// bytes, tagged with the current RUM correlation IDs. Returns `nil` when there are no live
    /// heap samples this period (nothing to attach). The caller bundles the returned bytes as a
    /// `heap.pprof` attachment on the wall/CPU profile event so both land on the same profile.
    ///
    /// RUM correlation IDs are attached as per-sample string labels (Go-aligned keys:
    /// `session_id`, `view_id`, `application_id`). All samples in the snapshot carry the same
    /// values because it is a point-in-time capture (documented approximation).
    ///
    /// `view.id` is stored in the attributes dictionary as `[String]` (the RUM SDK wraps it in
    /// an array); we take the first element as the label value.
    private func captureHeapPprof(attributes: [AttributeKey: AttributeValue]) -> Data? {
        var snapshot = dd_memory_snapshot_capture()
        defer { dd_memory_snapshot_destroy(&snapshot) }

        // Extract RUM correlation IDs from attributes using the same keys the wall
        // profiling path receives from the RUM feature message.
        // `view.id` is sent by the RUM SDK as [String] (array); take the first element.
        let sessionID     = attributes[RUMCoreContext.IDs.sessionID]     as? String
        let viewID        = (attributes[RUMCoreContext.IDs.viewID] as? [String])?.first
        let applicationID = attributes[RUMCoreContext.IDs.applicationID] as? String

        var raw: UnsafeMutablePointer<UInt8>? = nil
        // Pass each ID as a C string only when non-nil; the converter treats NULL and
        // empty-string identically (omits the label), so we pass NULL for absent IDs.
        let size = withOptionalCString(sessionID) { sidPtr in
            withOptionalCString(viewID) { vidPtr in
                withOptionalCString(applicationID) { aidPtr in
                    dd_memory_snapshot_to_pprof(&snapshot, sidPtr, vidPtr, aidPtr, &raw)
                }
            }
        }

        guard size > 0, let raw else {
            // No live heap samples this period — nothing to attach.
            return nil
        }

        let heapData = Data(bytes: raw, count: Int(size))
        free(raw)
        return heapData
    }

    /// Builds the standard comma-separated profiler tag string shared by all event types.
    private func profileTags(context: DatadogContext, operation: ProfilingOperation) -> String {
        [
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
        ].joined(separator: ",")
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

/// Calls `body` with a `UnsafePointer<CChar>?` for the given optional String.
/// Passes `nil` when `string` is `nil`; otherwise bridges via `withCString`.
/// This avoids duplicate `withCString` nesting with sentinel empty strings.
private func withOptionalCString<R>(
    _ string: String?,
    body: (UnsafePointer<CChar>?) -> R
) -> R {
    guard let string else { return body(nil) }
    return string.withCString { body($0) }
}
#endif
