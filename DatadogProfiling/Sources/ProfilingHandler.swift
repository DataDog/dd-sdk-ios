/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

// Keep this implementation-only. Otherwise, Swift 6 records DatadogMachProfiler as a
// transitive module dependency, but it is not distributed as an XCFramework.
@_implementationOnly import DatadogMachProfiler

internal protocol ProfilingHandler {
    var attributes: [AttributeKey: AttributeValue] { get }
    var currentServerTimeOffset: TimeInterval { get }

    var featureScope: FeatureScope { get }
    var telemetryController: ProfilingTelemetryController { get }
    var encoder: JSONEncoder { get }

    /// The `heap.pprof` bytes to attach to a CPU profile event of the given serialized size, or
    /// `nil` when there is nothing to attach or no room in the shared attachment budget.
    ///
    /// Declared here rather than only in the extension so the witness table dispatches to the
    /// conforming type — `DatadogProfiler` forwards it to `MemoryProfiler`, which owns the heap.
    func heapAttachment(
        fittingAlongside cpuProfileSize: Int,
        attributes: [AttributeKey: AttributeValue],
        operation: ProfilingOperation
    ) -> Data?
}

extension ProfilingHandler {
    /// A handler with no memory profiling behind it attaches nothing.
    func heapAttachment(
        fittingAlongside cpuProfileSize: Int,
        attributes: [AttributeKey: AttributeValue],
        operation: ProfilingOperation
    ) -> Data? {
        nil
    }

    /// Merges the RUM correlation IDs (vitals, hangs/errors, long tasks) into the base attributes
    /// and builds the matching `[RUMEvent]` timeline. Shared by the coupled (`write`) and heap-only
    /// (`writeHeapOnlyProfile`) paths so both events carry identical RUM correlation.
    private func rumCorrelation(
        rumVitals: [Vital],
        hangs: [DurationEvent]?,
        longTasks: [DurationEvent]?,
        errors: [DurationEvent]?
    ) -> (attributes: [AttributeKey: AttributeValue], rumEvents: [RUMEvent]) {
        var attributes = self.attributes

        if rumVitals.isEmpty == false {
            attributes[RUMCoreContext.IDs.vitalID] = rumVitals.map(\.id)
            attributes[RUMCoreContext.IDs.vitalLabel] = rumVitals.map(\.name)
        }
        // Hangs and memory warnings are both RUM errors and share one correlation list. It is
        // published only when it holds an id, matching how `vitalID` above already behaves — an
        // empty `error.id` array carries no information for the backend to join on.
        let errorIDs = (hangs?.map(\.id) ?? []) + (errors?.map(\.id) ?? [])
        if errorIDs.isEmpty == false {
            attributes[RUMCoreContext.IDs.errorID] = errorIDs
        }
        if let longTasks {
            attributes[RUMCoreContext.IDs.longTaskID] = longTasks.map { $0.id }
        }

        let rumEvents: [RUMEvent] = rumVitals.map(RUMEvent.vital)
            + (hangs?.map(RUMEvent.hang) ?? [])
            + (longTasks?.map(RUMEvent.longTask) ?? [])
            + (errors?.map(RUMEvent.error) ?? [])

        return (attributes, rumEvents)
    }

    func write(
        profile: OpaquePointer,
        operation: ProfilingOperation,
        rumVitals: [Vital],
        hangs: [DurationEvent]? = nil,
        longTasks: [DurationEvent]? = nil,
        errors: [DurationEvent]? = nil,
        captureHeapProfile: Bool = false
    ) {
        let (attributes, rumEvents) = rumCorrelation(
            rumVitals: rumVitals,
            hangs: hangs,
            longTasks: longTasks,
            errors: errors
        )

        self.writeProfilingEvent(
            with: profile,
            operation: operation,
            rumEvents: rumEvents,
            attributes: attributes,
            captureHeapProfile: captureHeapProfile
        )
    }

    private func writeProfilingEvent(
        with profile: OpaquePointer,
        operation: ProfilingOperation,
        rumEvents: [RUMEvent],
        attributes: [AttributeKey: AttributeValue],
        captureHeapProfile: Bool
    ) {
        let timeOffsetInNanoseconds = currentServerTimeOffset.dd.toInt64Nanoseconds
        dd_pprof_set_server_time_offset_ns(profile, timeOffsetInNanoseconds)

        var data: UnsafeMutablePointer<UInt8>?
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        let durationMs = (end - start).dd.toInt64Milliseconds
        let size = dd_pprof_serialize(profile, &data)

        guard let data else {
            telemetryController.sendNoData(durationMs: durationMs, for: operation)
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

        // Capture the heap only now that the CPU profile is known writable. Capturing it earlier
        // would drain the native alloc window (capture-and-reset) into a payload the guards above
        // then discard, permanently losing that window's `alloc_*` — and `sendProfile` advances
        // `memoryWindowStart` as though it had been covered.
        //
        // Go-aligned model: one event carries multiple pprof attachments (wall/CPU + heap) that the
        // backend merges into a single profile, so wall/CPU and memory appear together in the UI
        // instead of as two profiles.
        let heapPprof = captureHeapProfile
            ? heapAttachment(fittingAlongside: serializedProfileSize, attributes: attributes, operation: operation)
            : nil

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
                durationMs: durationMs,
                fileSize: Int64(clamping: size),
                for: operation
            )
        }
    }

    /// Emits a heap-only `ProfileEvent` — used when memory profiling is active but there is no
    /// writable CPU/wall profile this window (Option B independent emission). The event carries
    /// `heap.pprof` and the RUM-events timeline for the correlated vitals/hangs/long tasks (no
    /// `profile.pprof`); the transport already supports a nil CPU pprof. `start`/`end` bound the
    /// memory window (device time, adjusted to server time via the current offset). No-op when there
    /// are no heap samples this window.
    func writeHeapOnlyProfile(
        start: Date,
        end: Date,
        operation: ProfilingOperation,
        rumVitals: [Vital],
        hangs: [DurationEvent]? = nil,
        longTasks: [DurationEvent]? = nil,
        errors: [DurationEvent]? = nil
    ) {
        let (attributes, rumEvents) = rumCorrelation(
            rumVitals: rumVitals,
            hangs: hangs,
            longTasks: longTasks,
            errors: errors
        )
        // Here the heap is the *only* pprof, so it is asked to fit alongside nothing. There is also
        // nothing to fall back to: an oversized snapshot is dropped outright by `heapAttachment`
        // (with telemetry) rather than written into a metadata block the writer would silently
        // discard, leaving an event that can never upload.
        guard let heapPprof = heapAttachment(
            fittingAlongside: 0,
            attributes: attributes,
            operation: operation
        ) else {
            return
        }

        let offset = currentServerTimeOffset
        let serverStart = start.addingTimeInterval(offset)
        let serverEnd = end.addingTimeInterval(offset)
        let durationNs = (serverEnd.timeIntervalSince1970 - serverStart.timeIntervalSince1970).dd.toInt64Nanoseconds

        featureScope.eventWriteContext { context, writer in
            let event = ProfileEvent(
                family: Constants.family,
                runtime: Constants.runtime,
                version: Constants.version,
                start: serverStart,
                end: serverEnd,
                attachments: [
                    ProfileAttachments.Constants.rumEventsFilename,
                    ProfileAttachments.Constants.heapFilename
                ],
                tags: self.profileTags(context: context, operation: operation),
                additionalAttributes: attributes
            )
            let rumEventsData = try? self.encoder.encode(rumEvents)
            let attachments = ProfileAttachments(pprof: nil, rumEvents: rumEventsData, heapPprof: heapPprof)
            writer.write(value: event, metadata: attachments)
            self.telemetryController.sendProfile(
                durationNs: durationNs,
                fileSize: Int64(clamping: heapPprof.count),
                for: operation
            )
        }
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

#endif
