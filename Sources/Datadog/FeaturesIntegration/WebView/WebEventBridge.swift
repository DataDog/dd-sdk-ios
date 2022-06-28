/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias JSON = [String: Any]

internal protocol WebLogEventConsumer {
    func consume(event: JSON, internalLog: Bool) throws
}

internal protocol WebRUMEventConsumer {
    func consume(event: JSON) throws
}

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
        static let eventTypeInternalLog = "internal_log"
    }

    private let logEventConsumer: WebLogEventConsumer?
    private let rumEventConsumer: WebRUMEventConsumer?

    init(logEventConsumer: WebLogEventConsumer?, rumEventConsumer: WebRUMEventConsumer?) {
        self.logEventConsumer = logEventConsumer
        self.rumEventConsumer = rumEventConsumer
    }

    func consume(_ anyMessage: Any) throws {
        guard let message = anyMessage as? String else {
            throw WebEventError.invalidMessage(description: String(describing: anyMessage))
        }
        let eventJSON = try parse(message)
        guard let eventType = eventJSON[Constants.eventTypeKey] as? String else {
            throw WebEventError.missingKey(key: Constants.eventTypeKey)
        }
        guard let wrappedEvent = eventJSON[Constants.eventKey] as? JSON else {
            throw WebEventError.missingKey(key: Constants.eventKey)
        }

        if eventType == Constants.eventTypeLog ||
            eventType == Constants.eventTypeInternalLog {
            if let consumer = logEventConsumer {
                try consumer.consume(
                    event: wrappedEvent,
                    internalLog: (eventType == Constants.eventTypeInternalLog)
                )
            } else {
                DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
            }
        } else {
            if let consumer = rumEventConsumer {
                try consumer.consume(event: wrappedEvent)
            } else {
                DD.logger.warn("A WebView RUM event is lost because RUM is disabled in the SDK")
           }
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
