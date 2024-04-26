/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogCore

class ExtensionBackgroundTaskCoordinatorTests: XCTestCase {
    var processInfoSpy: ProcessInfoSpy! // swiftlint:disable:this implicitly_unwrapped_optional
    var coordinator: ExtensionBackgroundTaskCoordinator! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        processInfoSpy = ProcessInfoSpy()
        coordinator = ExtensionBackgroundTaskCoordinator(
            processInfo: processInfoSpy
        )
    }

    func testBeginBackgroundTask() {
        coordinator?.beginBackgroundTask()

        XCTAssertEqual(processInfoSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(processInfoSpy?.endBackgroundTaskCalled, false)
    }

    func testEndBackgroundTask() throws {
        coordinator?.beginBackgroundTask()
        coordinator?.endBackgroundTask()

        XCTAssertEqual(processInfoSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(processInfoSpy?.endBackgroundTaskCalled, true)
    }

    func testEndBackgroundTaskNotCalledWhenNotBegan() throws {
        coordinator?.endBackgroundTask()

        XCTAssertEqual(processInfoSpy?.beginBackgroundTaskCalled, false)
        XCTAssertEqual(processInfoSpy?.endBackgroundTaskCalled, false)
    }

    func testBeginEndsPreviousTask() throws {
        coordinator?.beginBackgroundTask()
        coordinator?.beginBackgroundTask()

        XCTAssertEqual(processInfoSpy?.beginBackgroundTaskCalled, true)
        XCTAssertEqual(processInfoSpy?.endBackgroundTaskCalled, true)
    }
}

class ProcessInfoSpy: ProcessInfoActivityCoordinator {
    var beginBackgroundTaskCalled = false
    var endBackgroundTaskCalled = false

    func beginActivity(options: ProcessInfo.ActivityOptions, reason: String) -> any NSObjectProtocol {
        beginBackgroundTaskCalled = true
        return NSObject()
    }

    func endActivity(_ activity: any NSObjectProtocol) {
        endBackgroundTaskCalled = true
    }
}
