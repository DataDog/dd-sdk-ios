/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS) && !os(macOS)

/// Writes captured profiles together when they share a RUM context.
internal final class ProfileWriter: @unchecked Sendable {
    private let featureScope: FeatureScope
    private let telemetryController: ProfilingTelemetryController
    private let encoder: JSONEncoder

    init(
        featureScope: FeatureScope,
        telemetryController: ProfilingTelemetryController = .init(),
        encoder: JSONEncoder = .init()
    ) {
        self.featureScope = featureScope
        self.telemetryController = telemetryController
        self.encoder = encoder
    }

    func write(_ snapshots: [ProfileSnapshot], operation: ProfilingOperation) {
        var filenames = Set<String>()
        let snapshots = snapshots.filter { snapshot in
            guard filenames.insert(snapshot.attachment.filename).inserted else {
                DD.logger.debug("Dropping duplicated profile snapshot '\(snapshot.attachment.filename)'.")
                return false
            }
            return true
        }

        guard !snapshots.isEmpty else {
            return
        }
        let memoryDiagnostics = snapshots.compactMap(\.memoryDiagnostics).first
        var profileTypes: [ProfilingSessionMetric.ProfileType] = []
        if snapshots.contains(where: { $0.attachment.filename == ProfileAttachments.Constants.pprofFilename }) {
            profileTypes.append(.cpu)
        }
        if snapshots.contains(where: { $0.attachment.filename == ProfileAttachments.Constants.heapPprofFilename }) {
            profileTypes.append(.memory)
        }

        // CPU's RUM timeline supports event-range selection; heap aggregates cannot be sliced.
        // Keep CPU events and attributes regardless of completion order, without merging heap events.
        // Another provider supplies RUM data when CPU has none, including memory-only captures.
        let cpuSnapshot = snapshots.first {
            $0.attachment.filename == ProfileAttachments.Constants.pprofFilename
        }
        let rumSnapshot = cpuSnapshot?.rumEvents.isEmpty == false
            ? cpuSnapshot
            : snapshots.first(where: { !$0.rumEvents.isEmpty })
        guard let first = snapshots.first, let rumSnapshot else {
            if memoryDiagnostics != nil {
                telemetryController.sendProfileDropped(
                    for: operation,
                    profileTypes: profileTypes,
                    memoryDiagnostics: memoryDiagnostics
                )
            }
            return
        }

        // This writer serves one RUM application; profiler queues can straddle a session change.
        let sessionIDs = snapshots.compactMap { snapshot in
            snapshot.attributes[RUMCoreContext.IDs.sessionID] as? String ?? snapshot.rumContext?.sessionID
        }
        guard Set(sessionIDs).count <= 1 else {
            writeSeparately(snapshots, operation: operation)
            return
        }
        let rumEvents = rumSnapshot.rumEvents
        var pprofs: [PprofAttachment] = []
        var profileSize = 0
        // The event envelopes the attachment ranges; each pprof retains its own time bounds.
        var start = first.start
        var end = first.end

        for snapshot in snapshots {
            guard snapshot.attachment.data.count <= Int(ProfilerFeature.Constants.maxObjectSize) - profileSize else {
                if snapshots.count > 1 {
                    writeSeparately(snapshots, operation: operation, sharingRUMDataFrom: rumSnapshot)
                } else {
                    telemetryController.sendProfileDropped(
                        for: operation,
                        reason: .profileTooLarge,
                        profileTypes: profileTypes,
                        memoryDiagnostics: memoryDiagnostics
                    )
                }
                return
            }

            profileSize += snapshot.attachment.data.count
            pprofs.append(snapshot.attachment)
            start = min(start, snapshot.start)
            end = max(end, snapshot.end)
        }

        let attributes = attributes(for: rumSnapshot)
        featureScope.eventWriteContext { [attributes, pprofs, start, end, profileSize] context, writer in
            guard let rumEventsData = try? self.encoder.encode(rumEvents) else {
                self.telemetryController.sendNoData(
                    durationMs: nil,
                    for: operation,
                    profileTypes: profileTypes,
                    memoryDiagnostics: memoryDiagnostics
                )
                return
            }
            let attachments = ProfileAttachments(pprofs: pprofs, rumEvents: rumEventsData)
            let event = ProfileEvent(
                family: Constants.family,
                runtime: Constants.runtime,
                version: Constants.version,
                start: start,
                end: end,
                attachments: pprofs.map(\.filename) + [ProfileAttachments.Constants.rumEventsFilename],
                tags: self.tags(for: operation, in: context),
                additionalAttributes: attributes
            )

            writer.write(value: event, metadata: attachments)
            self.telemetryController.sendProfile(
                durationMs: end.timeIntervalSince(start).dd.toInt64Milliseconds,
                fileSize: Int64(profileSize),
                for: operation,
                profileTypes: profileTypes,
                memoryDiagnostics: memoryDiagnostics
            )
        }
    }

    private func writeSeparately(
        _ snapshots: [ProfileSnapshot],
        operation: ProfilingOperation,
        sharingRUMDataFrom rumSnapshot: ProfileSnapshot? = nil
    ) {
        for snapshot in snapshots {
            if snapshot.rumEvents.isEmpty, let rumSnapshot {
                let correlatedSnapshot = ProfileSnapshot(
                    start: snapshot.start,
                    end: snapshot.end,
                    attachment: snapshot.attachment,
                    rumEvents: rumSnapshot.rumEvents,
                    attributes: rumSnapshot.attributes,
                    rumContext: rumSnapshot.rumContext,
                    memoryDiagnostics: snapshot.memoryDiagnostics
                )
                write([correlatedSnapshot], operation: operation)
            } else {
                write([snapshot], operation: operation)
            }
        }
    }

    private func attributes(for snapshot: ProfileSnapshot) -> [AttributeKey: AttributeValue] {
        var attributes = snapshot.attributes
        if let rum = snapshot.rumContext {
            if attributes[RUMCoreContext.IDs.applicationID] == nil {
                attributes[RUMCoreContext.IDs.applicationID] = rum.applicationID
            }
            if attributes[RUMCoreContext.IDs.sessionID] == nil {
                attributes[RUMCoreContext.IDs.sessionID] = rum.sessionID
            }
            if attributes[RUMCoreContext.IDs.viewID] == nil, let viewID = rum.viewID {
                attributes[RUMCoreContext.IDs.viewID] = [viewID]
            }
            if attributes[RUMCoreContext.IDs.viewName] == nil, let viewName = rum.viewName {
                attributes[RUMCoreContext.IDs.viewName] = [viewName]
            }
        }

        var vitalIDs: [String] = []
        var vitalLabels: [String] = []
        var errorIDs: [String] = []
        var longTaskIDs: [String] = []
        for event in snapshot.rumEvents {
            switch event {
            case .vital(let vital):
                vitalIDs.append(vital.id)
                vitalLabels.append(vital.name)
            case .hang(let hang):
                errorIDs.append(hang.id)
            case .longTask(let longTask):
                longTaskIDs.append(longTask.id)
            }
        }
        if !vitalIDs.isEmpty {
            attributes[RUMCoreContext.IDs.vitalID] = vitalIDs
            attributes[RUMCoreContext.IDs.vitalLabel] = vitalLabels
        }
        attributes[RUMCoreContext.IDs.errorID] = errorIDs
        attributes[RUMCoreContext.IDs.longTaskID] = longTaskIDs
        return attributes
    }

    private func tags(for operation: ProfilingOperation, in context: DatadogContext) -> String {
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
