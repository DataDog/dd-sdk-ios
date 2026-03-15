/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal typealias JSON = [String: Any]

private struct SendableJSON: @unchecked Sendable {
    var value: JSON
}

/// Receiver to consume a RUM event coming from Browser SDK.
internal final class WebViewEventReceiver: FeatureMessageReceiver, @unchecked Sendable {
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
    func receive(message: FeatureMessage) {
        switch message {
        case let .webview(.rum(event)):
            receive(rum: event)
        case let .webview(.telemetry(event)):
            receive(telemetry: event)
        default:
            break
        }
    }

    private func receive(rum event: JSON) {
        commandSubscriber.process(
            command: RUMKeepSessionAliveCommand(
                time: dateProvider.now,
                attributes: [:]
            )
        )

        let sendable = SendableJSON(value: event)
        Task { [self] in
            await writeRUMEvent(sendable.value)
        }
    }

    private func writeRUMEvent(_ event: JSON) async {
        guard let (context, writer) = await featureScope.eventWriteContext() else { return }
        guard let rum = context.additionalContext(ofType: RUMCoreContext.self) else {
            return
        }

        var webViewContext = context.additionalContext(ofType: RUMWebViewContext.self) ?? .init()
        var event = event

        if let date = event["date"] as? Int,
           let view = event["view"] as? JSON,
           let id = view["id"] as? String {
            let offsetMilliseconds: Int64

            if let offset = webViewContext.serverTimeOffset(forView: id) {
                offsetMilliseconds = offset.dd.toInt64Milliseconds
            } else {
                let offset = context.serverTimeOffset
                webViewContext.setServerTimeOffset(offset, forView: id)

                featureScope.set(context: webViewContext)
                offsetMilliseconds = offset.dd.toInt64Milliseconds
            }

            let correctedDate = Int64(date) + offsetMilliseconds
            event["date"] = correctedDate

            if let viewID = viewCache.lastView(before: correctedDate, hasReplay: true) {
                event[RUMViewEvent.CodingKeys.container.rawValue] = RUMViewEvent.Container(
                    source: RUMViewEvent.Container.Source(rawValue: context.source) ?? .ios,
                    view: RUMViewEvent.Container.View(id: viewID)
                )
            }
        }

        if var application = event["application"] as? JSON {
            application["id"] = rum.applicationID
            event["application"] = application
        }

        if var session = event["session"] as? JSON {
            session["id"] = rum.sessionID
            if context.hasReplay != true {
                session["has_replay"] = context.hasReplay
            }
            event["session"] = session
        }

        if var dd = event["_dd"] as? JSON, context.hasReplay != true {
            dd["replay_stats"] = nil
            event["_dd"] = dd
        }

        writer.write(value: AnyEncodable(event))
    }

    private func receive(telemetry event: JSON) {
        let sendable = SendableJSON(value: event)
        Task { [self] in
            await writeTelemetryEvent(sendable.value)
        }
    }

    private func writeTelemetryEvent(_ event: JSON) async {
        guard let (context, writer) = await featureScope.eventWriteContext() else { return }
        guard let rum = context.additionalContext(ofType: RUMCoreContext.self) else {
            return
        }

        var event = event

        if let date = event["date"] as? Int {
            event["date"] = Int64(date) + context.serverTimeOffset.dd.toInt64Milliseconds
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
