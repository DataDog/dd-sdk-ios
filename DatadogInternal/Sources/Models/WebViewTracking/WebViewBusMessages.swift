/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Typed-bus message for a Browser SDK log event forwarded through the WebView bridge.
public struct WebViewLogMessage: BusMessage {
    public static let key = "webview-log"

    /// The raw log event dictionary from the Browser SDK.
    public let event: WebViewMessage.Event

    public init(event: WebViewMessage.Event) {
        self.event = event
    }
}

/// Typed-bus message for a Browser SDK RUM or internal-telemetry event forwarded through the WebView bridge.
public struct WebViewRUMMessage: BusMessage {
    public static let key = "webview-rum"

    /// Distinguishes between a RUM event and a browser internal-telemetry event.
    public enum Kind {
        case rum
        case telemetry
    }

    /// Whether this is a RUM event or a browser telemetry event.
    public let kind: Kind
    /// The raw event dictionary from the Browser SDK.
    public let event: WebViewMessage.Event

    public init(kind: Kind, event: WebViewMessage.Event) {
        self.kind = kind
        self.event = event
    }
}

/// Typed-bus message for a Browser SDK Session Replay record forwarded through the WebView bridge.
public struct WebViewRecordMessage: BusMessage {
    public static let key = "webview-record"

    /// The raw record event dictionary from the Browser SDK.
    public let event: WebViewMessage.Event
    /// The browser view that produced the record.
    public let view: WebViewMessage.View

    public init(event: WebViewMessage.Event, view: WebViewMessage.View) {
        self.event = event
        self.view = view
    }
}
