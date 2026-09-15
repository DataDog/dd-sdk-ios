/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import TestUtilities
@testable import DatadogRUM

private class ViewControllerMock: DDViewController {
    var viewDidAppearExpectation: XCTestExpectation?
    var viewDidDisappearExpectation: XCTestExpectation?

    #if os(macOS)
    override func viewDidAppear() {
        super.viewDidAppear()
        viewDidAppearExpectation?.fulfill()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        viewDidDisappearExpectation?.fulfill()
    }
    #else
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearExpectation?.fulfill()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewDidDisappearExpectation?.fulfill()
    }
    #endif
}

class UIViewControllerSwizzlerTests: XCTestCase {
    #if os(macOS)
    private let handler = AppKitRUMViewsHandlerMock()
    #else
    private let handler = UIKitRUMViewsHandlerMock()
    #endif
    private lazy var swizzler = try! DDViewControllerSwizzler(handler: handler)

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

        // When
        #if os(macOS)
        handler.notifyViewDidAppear = { receivedViewController in
            XCTAssertTrue(receivedViewController === viewController)
            notifyHandlerExpectation.fulfill()
        }

        viewController.viewDidAppear()
        #else
        handler.notifyViewDidAppear = { receivedViewController, receivedAnimated in
            XCTAssertTrue(receivedViewController === viewController)
            XCTAssertEqual(receivedAnimated, animated)
            notifyHandlerExpectation.fulfill()
        }

        viewController.viewDidAppear(animated)
        #endif
        // Then
        wait(for: [notifyHandlerExpectation, callOriginalMethodExpectation], timeout: 0.5, enforceOrder: true)
    }

    func testWhenViewWillDisappearIsCalled_itNotifiesTheHandlerBeforeTheMethodExecutes() {
        let callOriginalMethodExpectation = expectation(description: "Call original method")
        let notifyHandlerExpectation = expectation(description: "Notify handler")

        let viewController = ViewControllerMock()
        viewController.viewDidDisappearExpectation = callOriginalMethodExpectation
        let animated = Bool.random()

        // When
        #if os(macOS)
        handler.notifyViewDidDisappear = { receivedViewController in
            XCTAssertTrue(receivedViewController === viewController)
            notifyHandlerExpectation.fulfill()
        }

        viewController.viewDidDisappear()
        #else
        handler.notifyViewDidDisappear = { receivedViewController, receivedAnimated in
            XCTAssertTrue(receivedViewController === viewController)
            XCTAssertEqual(receivedAnimated, animated)
            notifyHandlerExpectation.fulfill()
        }

        viewController.viewDidDisappear(animated)
        #endif

        // Then
        wait(for: [notifyHandlerExpectation, callOriginalMethodExpectation], timeout: 0.5, enforceOrder: true)
    }
}

#endif
