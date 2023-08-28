/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogCore

class UIKitBackgroundTaskCoordinatorTests: XCTestCase {
    var appSpy: AppSpy?
    var coordinator: UIKitBackgroundTaskCoordinator?

    override func setUp() {
        super.setUp()
        appSpy = AppSpy()
        coordinator = UIKitBackgroundTaskCoordinator(
            queue: DispatchQueue.main,
            app: appSpy
        )
    }

    func testBeginBackgroundTask() {
        let backgroundTaskIdentifier = coordinator?.beginBackgroundTask { }

        XCTAssertEqual(backgroundTaskIdentifier, 1)
        XCTAssertEqual(appSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(appSpy?.endBackgroundTaskCalled, false)
    }

    func testEndBackgroundTask() throws {
        let backgroundTaskIdentifier = try XCTUnwrap(coordinator?.beginBackgroundTask(expirationHandler: { }))
        coordinator?.endBackgroundTaskIfActive(backgroundTaskIdentifier)

        XCTAssertEqual(backgroundTaskIdentifier, 1)
        XCTAssertEqual(appSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(appSpy?.endBackgroundTaskCalled, true)
    }

    func testHanderFromTheSameQueue() {
        let expectHandlerCalled = expectation(description: "handler called")
        _ = coordinator?.beginBackgroundTask {
            XCTAssertEqual(Thread.current, Thread.main)
            expectHandlerCalled.fulfill()
        }
        appSpy?.fireHandler(from: .main)
        wait(for: [expectHandlerCalled])
    }

    func testHandlerFromDifferentQueue() {
        let expectHandlerCalled = expectation(description: "handler called")
        _ = coordinator?.beginBackgroundTask {
            XCTAssertEqual(Thread.current, Thread.main)
            expectHandlerCalled.fulfill()
        }
        appSpy?.fireHandler(from: .global(qos: .background))
        wait(for: [expectHandlerCalled])
    }
}

class AppSpy: UIKitAppBackgroundTaskCoordinator {
    var beginBackgroundTaskCalled = false
    var endBackgroundTaskCalled = false

    private var handler: (() -> Void)? = nil

    func beginBackgroundTask(expirationHandler handler: (() -> Void)?) -> UIBackgroundTaskIdentifier {
        self.handler = handler
        beginBackgroundTaskCalled = true
        return UIBackgroundTaskIdentifier(rawValue: 1)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        endBackgroundTaskCalled = true
    }

    func fireHandler(from: DispatchQueue) {
        from.async { [handler] in
            handler?()
        }
    }
}
