/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal typealias JSON = [String: Any]

internal protocol WebEventConsumer {
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
    }

    private let logEventConsumer: WebEventConsumer?
    private let rumEventConsumer: WebEventConsumer?

    init(logEventConsumer: WebEventConsumer?, rumEventConsumer: WebEventConsumer?) {
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

        if eventType == Constants.eventTypeLog {
            try logEventConsumer?.consume(event: wrappedEvent)
        } else {
            try rumEventConsumer?.consume(event: wrappedEvent)
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
