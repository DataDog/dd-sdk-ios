/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if !os(tvOS)
import WebKit

@testable import DatadogWebViewTracking

public final class DDUserContentController: WKUserContentController {
    public typealias NameHandlerPair = (name: String, handler: WKScriptMessageHandler)
    public private(set) var messageHandlers = [NameHandlerPair]()

    override public func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        messageHandlers.append((name: name, handler: scriptMessageHandler))
    }

    override public func removeScriptMessageHandler(forName name: String) {
        messageHandlers = messageHandlers.filter {
            return $0.name != name
        }
    }
}

public final class MockMessageHandler: NSObject, WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { }
}

public final class MockScriptMessage: WKScriptMessage {
    private let _body: Any
    private weak var _webView: WKWebView?

    public init(body: Any, webView: WKWebView? = nil) {
        _body = body
        _webView = webView
    }

    override public var body: Any { _body }
    override public weak var webView: WKWebView? { _webView }
}

#endif
