/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay

class RecordingTriggerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var recordingTrigger: RecordingTrigger!
    var recordingTriggerDelegateSpy: RecordingTriggerDelegateSpy!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        recordingTrigger = try RecordingTrigger()
        recordingTriggerDelegateSpy = RecordingTriggerDelegateSpy()
        recordingTrigger.delegate = recordingTriggerDelegateSpy
    }

    override func tearDownWithError() throws {
        recordingTrigger = nil
        recordingTriggerDelegateSpy = nil
    }

    func testRecordingTriggersInitialization() {
        XCTAssertEqual(recordingTriggerDelegateSpy.didTriggerCalledCount, 0)
    }

    func testStartAndStopRecordingTriggers() {
        recordingTrigger.startWatchingTriggers()

        XCTAssertEqual(recordingTriggerDelegateSpy.didTriggerCalledCount, 0)

        randomTrigger()

        XCTAssertEqual(recordingTriggerDelegateSpy.didTriggerCalledCount, 1)

        recordingTrigger.stopWatchingTriggers()

        XCTAssertEqual(recordingTriggerDelegateSpy.didTriggerCalledCount, 1)

        randomTrigger()

        XCTAssertEqual(recordingTriggerDelegateSpy.didTriggerCalledCount, 1)
    }

    func testNotifySendEventDoesNotTriggerOnInvalidEvent() {
        recordingTrigger.startWatchingTriggers()
        UIApplication.shared.sendEvent(UIEvent())

        XCTAssertEqual(recordingTriggerDelegateSpy.didTriggerCalledCount, 0)
    }

    private func randomTrigger() {
        if Int.random(in: 1...100) > 50 {
            let touch = UITouchMock()
            let event = UITouchEventMock(touches: [touch])
            UIApplication.shared.sendEvent(event)
        } else {
            UIView().layoutSubviews()
        }
    }
}

class RecordingTriggerDelegateSpy: RecordingTriggerDelegate {
    var didTriggerCalledCount = 0
    func didTrigger() {
        didTriggerCalledCount += 1
    }
}
#endif
