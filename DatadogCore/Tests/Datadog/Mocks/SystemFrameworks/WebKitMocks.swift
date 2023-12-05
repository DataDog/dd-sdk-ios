/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@testable import DatadogWebViewTracking

#if !os(tvOS)
import WebKit

final class WKUserContentControllerMock: WKUserContentController {
    private var handlers: [String: WKScriptMessageHandler] = [:]

    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        handlers[name] = scriptMessageHandler
    }

    override func removeScriptMessageHandler(forName name: String) {
        handlers[name] = nil
    }

    func send(body: Any) {
        let handler = handlers[DDScriptMessageHandler.name]
        let message = WKScriptMessageMock(body: body, name: DDScriptMessageHandler.name)
        handler?.userContentController(self, didReceive: message)
    }

    func scriptMessageHandler(forName name: String) -> WKScriptMessageHandler? {
        handlers[name]
    }

    func flush() {
        let handler = handlers[DDScriptMessageHandler.name] as? DDScriptMessageHandler
        handler?.flush()
    }
}

private final class WKScriptMessageMock: WKScriptMessage {
    private let _body: Any
    private let _name: String

    init(body: Any, name: String) {
        _body = body
        _name = name
    }

    override var body: Any { _body }
    override var name: String { _name }
}

#endif
