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
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        recordingTrigger = try RecordingTrigger()
    }

    override func tearDownWithError() throws {
        recordingTrigger = nil
    }

    func testStartAndStopRecordingTriggers() {
        var didTriggerCalledCount = 0
        recordingTrigger.startWatchingTriggers {
            didTriggerCalledCount += 1
        }

        XCTAssertEqual(didTriggerCalledCount, 0)

        randomTrigger()

        XCTAssertEqual(didTriggerCalledCount, 1)

        recordingTrigger.stopWatchingTriggers()

        XCTAssertEqual(didTriggerCalledCount, 1)

        randomTrigger()

        XCTAssertEqual(didTriggerCalledCount, 1)
    }

    func testNotifySendEventDoesNotTriggerOnInvalidEvent() {
        var didTriggerCalledCount = 0
        recordingTrigger.startWatchingTriggers {
            didTriggerCalledCount += 1
        }
        UIApplication.shared.sendEvent(UIEvent())

        XCTAssertEqual(didTriggerCalledCount, 0)
    }

    private func randomTrigger() {
        if Bool.random() {
            let touch = UITouchMock()
            let event = UITouchEventMock(touches: [touch])
            UIApplication.shared.sendEvent(event)
        } else {
            UIView().layoutSubviews()
        }
    }
}
#endif
