/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Intermediate type to parse WebView messages and send them to the message bus
internal struct WebViewMessage: Decodable {
    enum EventType: String, Decodable {
        case log
        case rum
        case view
        case action
        case resource
        case error
        case longTask = "long_task"
    }

    let eventType: EventType
    let event: AnyCodable
}

/// Errors that can be thrown when parsing a WebView message
internal enum WebViewMessageError: Error, Equatable {
    case dataSerialization(message: String)
    case invalidMessage(description: String)
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
