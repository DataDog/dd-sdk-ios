/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Errors that can be thrown when parsing a WebView message
internal enum WebViewMessageError: Error, Equatable {
    case dataSerialization(message: String)
    case invalidMessage(description: String)
}

/// Intermediate type to parse WebView messages and send them to the message bus
internal enum WebViewMessage {
    enum EventType: String, Decodable {
        case log
        case rum
        case view
        case action
        case resource
        case error
        case longTask = "long_task"
        case record
    }

    enum CodingKeys: CodingKey {
        case eventType
        case event
        case view
    }

    struct View: Decodable {
        let id: String
    }

    case log(AnyCodable)
    case rum(AnyCodable)
    case record(AnyCodable, View)
}

extension WebViewMessage {
    /// Parses a bag of data to a `WebViewMessage`
    /// 
    /// - Parameter body: Unstructured bag of data
    internal init(body: Any) throws {
        guard let message = body as? String else {
            throw WebViewMessageError.invalidMessage(description: String(describing: body))
        }

        guard let data = message.data(using: .utf8) else {
            throw WebViewMessageError.dataSerialization(message: message)
        }

        let decoder = JSONDecoder()
        self = try decoder.decode(WebViewMessage.self, from: data)
    }
}

extension WebViewMessage: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(EventType.self, forKey: .eventType)
        let event = try container.decode(AnyCodable.self, forKey: .event)

        switch eventType {
        case .log:
            self = .log(event)
        case .rum, .view, .action, .resource, .error, .longTask:
            self = .rum(event)
        case .record:
            let view = try container.decode(View.self, forKey: .view)
            self = .record(event, view)
        }
    }
}
