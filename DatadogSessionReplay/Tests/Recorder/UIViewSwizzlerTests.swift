/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay

class UIViewSwizzlerTests: XCTestCase {
    private let handler = UIViewHandlerMock()
    private lazy var swizzler = try! UIViewSwizzler(handler: handler)

    override func setUp() {
        super.setUp()
        swizzler.swizzle()
    }

    override func tearDown() {
        swizzler.unswizzle()
        super.tearDown()
    }

    func testWhenLayoutSubviewsIsCalled_itNotifiesTheHandler() {
        let expectation = self.expectation(description: "Notify handler")

        let anyView = UIView()

        handler.onSendEvent = { view in
            XCTAssertTrue(view === anyView)
            expectation.fulfill()
        }

        anyView.layoutSubviews()

        waitForExpectations(timeout: 1.5, handler: nil)
    }
}

class UIViewHandlerMock: UIViewHandler {
    var onSendEvent: ((UIView) -> Void)?

    func notify_layoutSubviews(view: UIView) {
        onSendEvent?(view)
    }
}
#endif
