/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

private class ViewControllerMock: UIViewController {
    var viewDidAppearExpectation: XCTestExpectation?
    var viewDidDisappearExpectation: XCTestExpectation?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearExpectation?.fulfill()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewDidDisappearExpectation?.fulfill()
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

    func testWhenViewDidAppearIsCalled_itNotifiesTheHandlerBeforeTheUserMethodExecutes() {
        let callOriginalMethodExpectation = expectation(description: "Call original method")
        let notifyHandlerExpectation = expectation(description: "Notify handler")

        let viewController = ViewControllerMock()
        viewController.viewDidAppearExpectation = callOriginalMethodExpectation
        let animated = Bool.random()

        handler.notifyViewDidAppear = { receivedViewController, receivedAnimated in
            XCTAssertTrue(receivedViewController === viewController)
            XCTAssertEqual(receivedAnimated, animated)
            notifyHandlerExpectation.fulfill()
        }

        // When
        viewController.viewDidAppear(animated)

        // Then
        wait(for: [notifyHandlerExpectation, callOriginalMethodExpectation], timeout: 0.5, enforceOrder: true)
    }

    func testWhenViewWillDisappearIsCalled_itNotifiesTheHandlerBeforeTheMethodExecutes() {
        let callOriginalMethodExpectation = expectation(description: "Call original method")
        let notifyHandlerExpectation = expectation(description: "Notify handler")

        let viewController = ViewControllerMock()
        viewController.viewDidDisappearExpectation = callOriginalMethodExpectation
        let animated = Bool.random()

        handler.notifyViewDidDisappear = { receivedViewController, receivedAnimated in
            XCTAssertTrue(receivedViewController === viewController)
            XCTAssertEqual(receivedAnimated, animated)
            notifyHandlerExpectation.fulfill()
        }

        // When
        viewController.viewDidDisappear(animated)

        // Then
        wait(for: [notifyHandlerExpectation, callOriginalMethodExpectation], timeout: 0.5, enforceOrder: true)
    }
}
