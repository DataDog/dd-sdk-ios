/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import WebKit
import TestUtilities

@testable import DatadogWebViewTracking

final class DDUserContentController: WKUserContentController {
    typealias NameHandlerPair = (name: String, handler: WKScriptMessageHandler)
    private(set) var messageHandlers = [NameHandlerPair]()

    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        messageHandlers.append((name: name, handler: scriptMessageHandler))
    }

    override func removeScriptMessageHandler(forName name: String) {
        messageHandlers = messageHandlers.filter {
            return $0.name != name
        }
    }
}

final class MockMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { }
}

final class MockScriptMessage: WKScriptMessage {
    let mockBody: Any

    init(body: Any) {
        self.mockBody = body
    }

    override var body: Any { return mockBody }
}

extension WebViewTracking.SessionReplayConfiguration.PrivacyLevel: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        .allow
    }

    public static func mockRandom() -> Self {
        [.allow, .mask, .maskUserInput].randomElement()!
    }
}
