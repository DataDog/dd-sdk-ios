/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal typealias JSON = [String: Any]

/// Receiver to consume a RUM event coming from Browser SDK.
internal final class WebViewEventReceiver: FeatureMessageReceiver {
    /// RUM feature scope.
    let featureScope: FeatureScope
    /// Subscriber that can process a `RUMKeepSessionAliveCommand`.
    let commandSubscriber: RUMCommandSubscriber

    /// The date provider.
    let dateProvider: DateProvider

    /// The view cache containing ids of current and previous views.
    let viewCache: ViewCache

    /// Creates a new receiver.
    ///
    /// - Parameters:
    ///   - dateProvider: The date provider.
    ///   - commandSubscriber: Subscriber that can process a `RUMKeepSessionAliveCommand`.
    init(
        featureScope: FeatureScope,
        dateProvider: DateProvider,
        commandSubscriber: RUMCommandSubscriber,
        viewCache: ViewCache
    ) {
        self.featureScope = featureScope
        self.commandSubscriber = commandSubscriber
        self.dateProvider = dateProvider
        self.viewCache = viewCache
    }

    /// Writes a Browser RUM event to the core.
    ///
    /// The receiver will inject current RUM context and apply server-time offset to the event.
    ///
    /// - Parameters:
    ///   - message: The message containing the Browser RUM event.
    ///   - core: The core to write the event.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case let .webview(.rum(event)):
            receive(rum: event)
        case let .webview(.telemetry(event)):
            receive(telemetry: event)
        default:
            return false
        }

        return true
    }

    private func receive(rum event: JSON) {
        commandSubscriber.process(
            command: RUMKeepSessionAliveCommand(
                time: dateProvider.now,
                attributes: [:]
            )
        )

        featureScope.eventWriteContext { context, writer in
            guard let rum = context.additionalContext(ofType: RUMCoreContext.self) else {
                return // Drop event if RUM is not enabled or RUM session is not sampled
            }

            var event = event

            if let date = event["date"] as? Int,
               let view = event["view"] as? JSON,
               let id = view["id"] as? String {
                let correctedDate = Int64(date) + self.offset(forView: id, context: context)
                event["date"] = correctedDate

                // Always inject the container source for webview events
                var container = RUMViewEvent.Container(
                    source: RUMViewEvent.Container.Source(rawValue: context.source) ?? .ios,
                    view: nil
                )

                // Add view ID if there's an active replay session
                if let viewID = self.viewCache.lastView(before: correctedDate, hasReplay: true) {
                    container = RUMViewEvent.Container(
                        source: RUMViewEvent.Container.Source(rawValue: context.source) ?? .ios,
                        view: RUMViewEvent.Container.View(id: viewID)
                    )
                }

                event[RUMViewEvent.CodingKeys.container.rawValue] = container
            }

            if var application = event["application"] as? JSON {
                application["id"] = rum.applicationID
                event["application"] = application
            }

            if var session = event["session"] as? JSON {
                session["id"] = rum.sessionID
                // Unset `has_replay` if native replay is disabled
                if context.hasReplay != true {
                    session["has_replay"] = context.hasReplay
                }

                event["session"] = session
            }

            if var dd = event["_dd"] as? JSON, context.hasReplay != true {
                // Remove stats if native replay is disabled
                dd["replay_stats"] = nil
                event["_dd"] = dd
            }

            writer.write(value: AnyEncodable(event))
        }
    }

    private func receive(telemetry event: JSON) {
        // RUM-2866: Update with dedicated telemetry track
        featureScope.eventWriteContext { context, writer in
            guard let rum = context.additionalContext(ofType: RUMCoreContext.self) else {
                return // Drop event if RUM is not enabled or RUM session is not sampled
            }

            var event = event

            if let date = event["date"] as? Int {
                event["date"] = Int64(date) + context.serverTimeOffset.toInt64Milliseconds
            }

            if var application = event["application"] as? JSON {
                application["id"] = rum.applicationID
                event["application"] = application
            }

            if var session = event["session"] as? JSON {
                session["id"] = rum.sessionID
                event["session"] = session
            }

            writer.write(value: AnyEncodable(event))
        }
    }

    // MARK: - Time offsets

    private var offsets: [(id: String, value: Int64)] = []

    private func offset(forView id: String, context: DatadogContext) -> Int64 {
        if let found = offsets.first(where: { $0.id == id }) {
            return found.value
        }

        let offset = context.serverTimeOffset.toInt64Milliseconds
        offsets.insert((id, offset), at: 0)
        // only retain 3 offsets
        offsets = Array(offsets.prefix(3))

        return offset
    }
}
