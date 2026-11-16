/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS) && !os(macOS)

/// Writes captured profiles and their shared RUM context as one profile event.
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
        guard let first = snapshots.first,
              let rumSnapshot = snapshots.first(where: { !$0.rumEvents.isEmpty }) else {
            return
        }

        for key in [RUMCoreContext.IDs.applicationID, RUMCoreContext.IDs.sessionID] {
            let identifiers = snapshots.compactMap { snapshot in
                let fallback = key == RUMCoreContext.IDs.applicationID ? snapshot.rumContext?.applicationID : snapshot.rumContext?.sessionID
                return snapshot.attributes[key] as? String ?? fallback
            }
            guard Set(identifiers).count <= 1 else {
                DD.logger.debug("Dropping profile snapshots with incompatible RUM contexts.")
                return
            }
        }
        let rumEvents = rumSnapshot.rumEvents
        var attributes = self.attributes(for: rumSnapshot)
        var pprofs: [PprofAttachment] = []
        var filenames = Set<String>()
        var profileSize = 0
        var start = first.start
        var end = first.end

        for snapshot in snapshots {
            guard filenames.insert(snapshot.attachment.filename).inserted else {
                DD.logger.debug("Dropping profile snapshots with duplicate attachment filenames.")
                return
            }
            guard snapshot.attachment.data.count <= Int(ProfilerFeature.Constants.maxObjectSize) - profileSize else {
                telemetryController.sendProfileDropped(for: operation, reason: .profileTooLarge)
                return
            }

            profileSize += snapshot.attachment.data.count
            pprofs.append(snapshot.attachment)
            start = min(start, snapshot.start)
            end = max(end, snapshot.end)
        }

        var vitalIDs: [String] = []
        var vitalLabels: [String] = []
        var errorIDs: [String] = []
        var longTaskIDs: [String] = []
        for event in rumEvents {
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

        featureScope.eventWriteContext { [attributes, pprofs, start, end, profileSize] context, writer in
            guard let rumEventsData = try? self.encoder.encode(rumEvents) else {
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
                tags: [
                    self.tag(Tag.Key.service, context.service),
                    self.tag(Tag.Key.version, context.version),
                    self.tag(Tag.Key.sdkVersion, context.sdkVersion),
                    self.tag(Tag.Key.profilerVersion, context.sdkVersion),
                    self.tag(Tag.Key.runtimeVersion, context.os.version),
                    self.tag(Tag.Key.env, context.env),
                    self.tag(Tag.Key.source, context.source),
                    self.tag(Tag.Key.language, Tag.Value.language),
                    self.tag(Tag.Key.format, Tag.Value.format),
                    self.tag(Tag.Key.remoteSymbols, Tag.Value.remoteSymbols),
                    self.tag(Tag.Key.operation, operation.rawValue)
                ].joined(separator: ","),
                additionalAttributes: attributes
            )

            writer.write(value: event, metadata: attachments)
            self.telemetryController.sendProfile(
                durationMs: end.timeIntervalSince(start).dd.toInt64Milliseconds,
                fileSize: Int64(profileSize),
                for: operation
            )
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
        return attributes
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
