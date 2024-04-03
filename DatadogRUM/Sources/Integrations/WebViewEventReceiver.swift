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

        featureScope.eventWriteContext { [featureScope] context, writer in
            guard let rumBaggage = context.baggages[RUMFeature.name] else {
                return // Drop event if RUM is not enabled or RUM session is not sampled
            }

            do {
                let rum: RUMCoreContext = try rumBaggage.decode()
                var event = event

                if let date = event["date"] as? Int {
                    let viewID = (event["view"] as? JSON)?["id"] as? String
                    let serverTimeOffsetInMs = self.getOffsetInMs(viewID: viewID, context: context)
                    let correctedDate = Int64(date) + serverTimeOffsetInMs
                    event["date"] = correctedDate

                    // Inject the container source and view id
                    if let viewID = self.viewCache.lastView(before: date, hasReplay: true) {
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
                    event["session"] = session
                }

                if var dd = event["_dd"] as? JSON {
                    var session = dd["session"] as? [String: Any] ?? [:]
                    session["plan"] = 1
                    dd["session"] = session
                    event["_dd"] = dd
                }

                writer.write(value: AnyEncodable(event))
            } catch {
                featureScope.telemetry.error("Failed to decode `RUMCoreContext`", error: error)
            }
        }
    }

    private func receive(telemetry event: JSON) {
        // RUM-2866: Update with dedicated telemetry track
        featureScope.eventWriteContext { [featureScope] context, writer in
            guard let rumBaggage = context.baggages[RUMFeature.name] else {
                return // Drop event if RUM is not enabled or RUM session is not sampled
            }

            do {
                let rum: RUMCoreContext = try rumBaggage.decode()
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
            } catch {
                featureScope.telemetry.error("Failed to decode `RUMCoreContext`", error: error)
            }
        }
    }

    // MARK: - Time offsets

    private typealias Offset = Int64
    private typealias ViewIDOffsetPair = (viewID: String, offset: Offset)
    private var viewIDOffsetPairs = [ViewIDOffsetPair]()

    private func getOffsetInMs(viewID: String?, context: DatadogContext) -> Offset {
        guard let viewID = viewID else {
            return 0
        }

        purgeOffsets()
        let found = viewIDOffsetPairs.first { $0.viewID == viewID }
        if let found = found {
            return found.offset
        }
        let offset = context.serverTimeOffset.toInt64Milliseconds
        viewIDOffsetPairs.insert((viewID: viewID, offset: offset), at: 0)
        return offset
    }

    private func purgeOffsets() {
        while viewIDOffsetPairs.count > 3 {
            _ = viewIDOffsetPairs.popLast()
        }
    }
}
