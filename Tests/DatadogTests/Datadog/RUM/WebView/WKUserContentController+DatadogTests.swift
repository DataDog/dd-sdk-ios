/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import WebKit
@testable import Datadog

final class DDUserContentController: WKUserContentController {
    private(set) var messageHandlerNames = [String]()

    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        messageHandlerNames.append(name)
    }
}

class WKUserContentController_DatadogTests: XCTestCase {
    func testItAddsUserScriptAndMessageHandler() throws {
        let mockSanitizer = MockHostsSanitizer()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        controller.__addDatadogMessageHandler(allowedWebViewHosts: ["datadoghq.com"], hostsSanitizer: mockSanitizer)

        XCTAssertEqual(controller.userScripts.count, initialUserScriptCount + 1)
        XCTAssertEqual(controller.messageHandlerNames, ["DatadogEventBridge"])
        XCTAssertEqual(mockSanitizer.sanitizations.count, 1)
        let sanitization = try XCTUnwrap(mockSanitizer.sanitizations.first)
        XCTAssertEqual(sanitization.hosts, ["datadoghq.com"])
        XCTAssertEqual(sanitization.warningMessage, "The allowed WebView host configured for Datadog SDK is not valid")
    }
}
