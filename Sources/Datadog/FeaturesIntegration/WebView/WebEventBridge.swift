/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal enum WebEventError: Error, Equatable {
    case dataSerialization(message: String)
    case JSONDeserialization(rawJSONDescription: String)
    case invalidMessage(description: String)
    case missingKey(key: String)
}

internal class WebEventBridge {
    struct Constants {
        static let eventTypeKey = "eventType"
        static let eventKey = "event"
        static let eventTypeLog = "log"
        static let browserLog = "browser-log"
        static let browserEvent = "browser-rum-event"
    }

    private let core: DatadogCoreProtocol

    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    func consume(_ anyMessage: Any) throws {
        guard let message = anyMessage as? String else {
            throw WebEventError.invalidMessage(description: String(describing: anyMessage))
        }

        let eventJSON = try parse(message)

        guard let type = eventJSON[Constants.eventTypeKey] as? String else {
            throw WebEventError.missingKey(key: Constants.eventTypeKey)
        }

        guard let event = eventJSON[Constants.eventKey] as? JSON else {
            throw WebEventError.missingKey(key: Constants.eventKey)
        }

        if type == Constants.eventTypeLog {
            core.send(message: .custom(key: Constants.browserLog, baggage: .init(event)), else: {
                DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
            })
        } else {
            core.send(message: .custom(key: Constants.browserEvent, baggage: .init(event)), else: {
                DD.logger.warn("A WebView RUM event is lost because RUM is disabled in the SDK")
            })
        }
    }

    private func parse(_ message: String) throws -> JSON {
        guard let data = message.data(using: .utf8) else {
            throw WebEventError.dataSerialization(message: message)
        }
        let rawJSON = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = rawJSON as? JSON else {
            throw WebEventError.JSONDeserialization(rawJSONDescription: String(describing: rawJSON))
        }
        return json
    }
}
