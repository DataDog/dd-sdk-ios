/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
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
    ///   - featureScope: The feature scope.
    ///   - dateProvider: The date provider.
    ///   - commandSubscriber: Subscriber that can process a `RUMKeepSessionAliveCommand`.
    ///   - viewCache: The RUM view cache.
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
        let browserMessage: WebViewMessage
        let capturedMessage: WebViewMessageWithRUMContext?
        switch message {
        case let .webview(message):
            browserMessage = message
            capturedMessage = nil
        case let .payload(message as WebViewMessageWithRUMContext):
            browserMessage = message.message
            capturedMessage = message
        default:
            return false
        }

        switch browserMessage {
        case let .rum(event):
            receive(rum: event, capture: capturedMessage, core: core)
        case let .telemetry(event):
            receive(telemetry: event, capture: capturedMessage, core: core)
        default:
            return false
        }

        return true
    }

    private func receive(rum event: JSON, capture: WebViewMessageWithRUMContext?, core: DatadogCoreProtocol) {
        if let capture {
            guard capture.capture.owner.isValid,
                  RUMContextHandoff.owner(in: core) === capture.capture.owner else {
                return
            }
        }
        if capture == nil {
            keepRUMSessionAlive()
        }

        featureScope.eventWriteContext { context, writer in
            let currentRUM = context.additionalContext(ofType: RUMCoreContext.self)
            let rum: RUMCoreContext?
            if let capture {
                rum = capture.rumContext(for: RUMContextHandoff.owner(in: core), sessionID: currentRUM?.sessionID)
            } else {
                rum = currentRUM
            }
            guard let rum, rum.sessionSampler.isSampled else {
                return // Drop unavailable or unsampled native ownership without borrowing another session.
            }

            if let capture {
                self.keepRUMSessionAlive(capture: capture.capture)
            }
            var webViewContext = context.additionalContext(ofType: RUMWebViewContext.self) ?? .init()
            var event = event
            if capture != nil {
                // Supplied containers have no proven native ownership, including malformed events.
                event[RUMViewEvent.CodingKeys.container.rawValue] = nil
            }

            event["ddtags"] = DDTag.merge(context.ddTags, with: event["ddtags"] as? String)

            if let date = event["date"] as? Int,
               let view = event["view"] as? JSON,
               let id = view["id"] as? String {
                let offsetMilliseconds: Int64

                if let offset = webViewContext.serverTimeOffset(forView: id) {
                    offsetMilliseconds = offset.dd.toInt64Milliseconds
                } else {
                    let offset = context.serverTimeOffset
                    webViewContext.setServerTimeOffset(offset, forView: id)

                    self.featureScope.set(context: webViewContext)
                    offsetMilliseconds = offset.dd.toInt64Milliseconds
                }

                let correctedDate = Int64(date) + offsetMilliseconds
                event["date"] = correctedDate

                // Inject the container source and view id
                let viewID: String?
                if let capture {
                    // A captured native callback can only use history from its originating scene.
                    viewID = capture.capture.value.sceneIdentifier.flatMap {
                        self.viewCache.lastView(before: correctedDate, hasReplay: true, in: RUMSceneIdentifier(rawValue: $0))
                    }
                } else {
                    viewID = self.viewCache.lastView(before: correctedDate, hasReplay: true)
                }
                if let viewID {
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
                // Unset `has_replay` if native replay is disabled
                if context.hasReplay != true {
                    session["has_replay"] = context.hasReplay
                }

                event["session"] = session
            }

            if var dd = event["_dd"] as? JSON {
                if context.hasReplay != true {
                    // Remove stats if native replay is disabled
                    dd["replay_stats"] = nil
                    event["_dd"] = dd
                }
                if dd["rule_psr"] != nil,
                   let networkInstrumentation = core.feature(
                    named: Feature.networkInstrumentation,
                    type: DistributedTracingSampleRateProvider.self
                   ),
                   let distributedTracingSampleRate = networkInstrumentation.distributedTracingSampleRate {
                    dd["rule_psr"] = distributedTracingSampleRate.percentageProportion
                    event["_dd"] = dd
                }
            }

            // Add native anonymous_id to the event's usr object
            if let anonymousId = context.userInfo?.anonymousId {
                var usr = event["usr"] as? JSON ?? [:]
                usr["anonymous_id"] = anonymousId
                event["usr"] = usr
            }

            writer.write(value: AnyEncodable(event))
        }
    }

    private func keepRUMSessionAlive(capture: RUMContextHandoff.Capture? = nil) {
        commandSubscriber.process(
            command: RUMKeepSessionAliveCommand(time: dateProvider.now, attributes: [:], capture: capture)
        )
    }

    private func receive(telemetry event: JSON, capture: WebViewMessageWithRUMContext?, core: DatadogCoreProtocol) {
        // RUM-2866: Update with dedicated telemetry track
        featureScope.eventWriteContext { context, writer in
            let currentRUM = context.additionalContext(ofType: RUMCoreContext.self)
            let rum: RUMCoreContext?
            if let capture {
                rum = capture.rumContext(for: RUMContextHandoff.owner(in: core), sessionID: currentRUM?.sessionID)
            } else {
                rum = currentRUM
            }
            guard let rum, rum.sessionSampler.isSampled else {
                return // Drop unavailable or unsampled native ownership without borrowing another session.
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
}
