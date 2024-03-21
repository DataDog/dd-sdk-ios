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
        dateProvider: DateProvider,
        commandSubscriber: RUMCommandSubscriber,
        viewCache: ViewCache
    ) {
        self.commandSubscriber = commandSubscriber
        self.dateProvider = dateProvider
        self.viewCache = viewCache
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .webview(.rum(event)) = message else {
            return false
        }

        commandSubscriber.process(
            command: RUMKeepSessionAliveCommand(
                time: dateProvider.now,
                attributes: [:]
            )
        )

        core.scope(for: RUMFeature.name)?.eventWriteContext { [weak core] context, writer in
            guard let rumBaggage = context.baggages[RUMFeature.name] else {
                return // Drop event if RUM is not enabled or RUM session is not sampled
            }

            do {
                let rum: RUMCoreContext = try rumBaggage.decode()
                var event = event

                if
                    let date = event["date"] as? Int,
                    let view = event["view"] as? JSON,
                    let id = view["id"] as? String
                {
                    let correctedDate = Int64(date) + self.offset(forView: id, context: context)
                    event["date"] = correctedDate

                    // Inject the container source and view id
                    if let viewID = self.viewCache.lastView(before: correctedDate, hasReplay: true) {
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
                core?.telemetry.error("Failed to decode `RUMCoreContext`", error: error)
            }
        }

        return true
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
