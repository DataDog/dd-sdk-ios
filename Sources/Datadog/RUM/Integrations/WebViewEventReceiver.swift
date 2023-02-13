/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal typealias JSON = [String: Any]

/// Receiver to consume a RUM event coming from Browser SDK.
internal final class WebViewEventReceiver: FeatureMessageReceiver {
    /// Defines keys referencing Browser event message on the bus.
    enum MessageKeys {
        /// The key references a browser event message.
        static let browserEvent = "browser-rum-event"
    }

    /// Subscriber that can process a `RUMKeepSessionAliveCommand`.
    let commandSubscriber: RUMCommandSubscriber

    /// The date provider.
    let dateProvider: DateProvider

    /// Creates a new receiver.
    ///
    /// - Parameters:
    ///   - dateProvider: The date provider.
    ///   - commandSubscriber: Subscriber that can process a `RUMKeepSessionAliveCommand`.
    init(
        dateProvider: DateProvider,
        commandSubscriber: RUMCommandSubscriber = GlobalRUMCommandSubscriber()
    ) {
        self.commandSubscriber = commandSubscriber
        self.dateProvider = dateProvider
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        if case let .custom(key, baggage) = message, key == MessageKeys.browserEvent {
            write(event: baggage.attributes, to: core)
            return true
        }

        return false
    }

    /// Writes a Browser RUM event to the core.
    ///
    /// The receiver will inject current RUM context and apply server-time offset to the event.
    ///
    /// - Parameters:
    ///   - event: The Browser RUM event.
    ///   - core: The core to write the event.
    func write(event: JSON, to core: DatadogCoreProtocol) {
        commandSubscriber.process(
            command: RUMKeepSessionAliveCommand(
                time: dateProvider.now,
                attributes: [:]
            )
        )

        core.v1.scope(for: RUMFeature.self)?.eventWriteContext { context, writer in
            guard let attributes: [String: String?] = context.featuresAttributes["rum"]?.ids, !attributes.isEmpty else {
                return writer.write(value: AnyEncodable(event))
            }
            var event = event

            if let date = event["date"] as? Int {
                let viewID = (event["view"] as? JSON)?["id"] as? String
                let serverTimeOffsetInMs = self.getOffsetInMs(viewID: viewID, context: context)
                let correctedDate = Int64(date) + serverTimeOffsetInMs
                event["date"] = correctedDate
            }

            let applicationID = attributes[RUMContextAttributes.IDs.applicationID]
            if let applicationID = applicationID, var application = event["application"] as? JSON {
                application["id"] = applicationID
                event["application"] = application
            }

            let sessionID = attributes[RUMContextAttributes.IDs.sessionID]
            if let sessionID = sessionID, var session = event["session"] as? JSON {
                session["id"] = sessionID
                event["session"] = session
            }

            if var dd = event["_dd"] as? JSON, var dd_sesion = dd["session"] as? [String: Int] {
                dd_sesion["plan"] = 1
                dd["session"] = dd_sesion
                event["_dd"] = dd
            }

            writer.write(value: AnyEncodable(event))
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
