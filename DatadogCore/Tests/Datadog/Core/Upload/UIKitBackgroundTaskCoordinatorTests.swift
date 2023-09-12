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
            app: appSpy
        )
    }

    func testBeginBackgroundTask() {
        coordinator?.beginBackgroundTask()

        XCTAssertEqual(appSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(appSpy?.endBackgroundTaskCalled, false)
    }

    func testEndBackgroundTask() throws {
        coordinator?.beginBackgroundTask()
        coordinator?.endBackgroundTask()

        XCTAssertEqual(appSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(appSpy?.endBackgroundTaskCalled, true)
    }

    func testEndBackgroundTaskNotCalledWhenNotBegan() throws {
        coordinator?.endBackgroundTask()

        XCTAssertEqual(appSpy?.beginBackgroundTaskCalled, false)
        XCTAssertEqual(appSpy?.endBackgroundTaskCalled, false)
    }

    func testBeginEndsPreviousTask() throws {
        coordinator?.beginBackgroundTask()
        coordinator?.beginBackgroundTask()

        XCTAssertEqual(appSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(appSpy?.endBackgroundTaskCalled, true)
    }
}

class AppSpy: UIKitAppBackgroundTaskCoordinator {
    var beginBackgroundTaskCalled = false
    var endBackgroundTaskCalled = false

    var handler: (() -> Void)? = nil

    func beginBackgroundTask(expirationHandler handler: (() -> Void)?) -> UIBackgroundTaskIdentifier {
        self.handler = handler
        beginBackgroundTaskCalled = true
        return UIBackgroundTaskIdentifier(rawValue: 1)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        endBackgroundTaskCalled = true
    }
}
