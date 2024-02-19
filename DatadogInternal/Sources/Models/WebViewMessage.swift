/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A web-view message is transmitted by the `DatadogWebViewTracking` module
/// on the message-bus.
/// 
/// Such message is decoded from Browser SDK events sent over the JS bridge.
public enum WebViewMessage {
    /// The Browser event types that can be transmitted over the bridge.
    public enum EventType: String, Decodable {
        case log
        case rum
        case view
        case action
        case resource
        case error
        case longTask = "long_task"
        case record
    }

    /// Raw event dictionary.
    public typealias Event = [String: Any]

    public struct View: Decodable {
        public let id: String
    }

    /// A browser log event.
    case log(Event)
    /// A browser rum event.
    case rum(Event)
    /// A browser session-replay record.
    case record(Event, View)
}

/// A web-view record associated with a `slot_id`.
///
/// The `slot_id` is the `webView.configuration.userContentController.hash` value
/// and is used to match a browser record with the web-view container.
public struct WebViewRecord {
    /// The record event.
    public let event: WebViewMessage.Event
    /// The Browser SDK view of the record.
    public let view: WebViewMessage.View
    /// The container `slot_id`.
    public let slotId: String

    public init(
        event: WebViewMessage.Event,
        view: WebViewMessage.View,
        slotId: String
    ) {
        self.event = event
        self.view = view
        self.slotId = slotId
    }
}

extension WebViewMessage: Decodable {
    enum CodingKeys: CodingKey {
        case eventType
        case event
        case view
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(EventType.self, forKey: .eventType)
        let event = try container.decode(AnyDecodable.self, forKey: .event)

        guard let event = event.value as? Event else {
            throw DecodingError.typeMismatch(
                Event.self,
                DecodingError.Context(
                    codingPath: [CodingKeys.event],
                    debugDescription: "The Browser Record event is not a dictionary"
                )
            )
        }

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
