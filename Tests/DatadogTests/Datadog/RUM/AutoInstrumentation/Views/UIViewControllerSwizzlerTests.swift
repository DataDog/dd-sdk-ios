/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension UIViewControllerSwizzler {
    func unswizzle() {
        viewWillAppear.unswizzle()
        viewWillDisappear.unswizzle()
    }
}

class UIViewControllerSwizzlerTests: XCTestCase {
    private let handler = UIKitRUMViewsHandlerMock()
    private lazy var swizzler = try! UIViewControllerSwizzler(handler: handler)

    override func setUp() {
        super.setUp()
        swizzler.swizzle()
    }

    override func tearDown() {
        swizzler.unswizzle()
        super.tearDown()
    }

    func testWhenViewWillAppearIsCalled_itNotifiesTheHandler() {
        let expectation = self.expectation(description: "Notify handler")
        let viewController = createMockView()
        let animated = Bool.random()

        handler.onViewWillAppear = { receivedViewController, receivedAnimated in
            XCTAssertTrue(receivedViewController === viewController)
            XCTAssertEqual(receivedAnimated, animated)
            expectation.fulfill()
        }

        viewController.viewWillAppear(animated)

        waitForExpectations(timeout: 0.5, handler: nil)
    }

    func testWhenViewWillDisappearIsCalled_itNotifiesTheHandler() {
        let expectation = self.expectation(description: "Notify handler")
        let viewController = createMockView()
        let animated = Bool.random()

        handler.onViewWillDisappear = { receivedViewController, receivedAnimated in
            XCTAssertTrue(receivedViewController === viewController)
            XCTAssertEqual(receivedAnimated, animated)
            expectation.fulfill()
        }

        viewController.viewWillDisappear(animated)

        waitForExpectations(timeout: 0.5, handler: nil)
    }
}
