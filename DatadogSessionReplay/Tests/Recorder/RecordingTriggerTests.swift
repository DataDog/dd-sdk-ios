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
    var recordingCoordinatorSpy: RecordingCoordinatorSpy!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        recordingCoordinatorSpy = RecordingCoordinatorSpy()
        recordingTrigger = try RecordingTrigger(
            recordingCoordinator: recordingCoordinatorSpy,
            shouldStartWatchingTriggers: false
        )
    }

    override func tearDownWithError() throws {
        recordingTrigger = nil
        recordingCoordinatorSpy = nil
    }

    func testRecordingTriggersInitialization() {
        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 0)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 0)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 0)
    }

    func testStartAndStopRecordingTriggers() {
        recordingTrigger.startWatchingTriggers()

        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 0)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 0)

        randomTrigger()

        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 0)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 1)

        recordingTrigger.stopWatchingTriggers()

        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 1)

        randomTrigger()

        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 1)
    }

    func testNotifySendEventDoesNotTriggerOnInvalidEvent() {
        recordingTrigger.startWatchingTriggers()
        UIApplication.shared.sendEvent(UIEvent())

        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 0)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 0)
    }

    func testStartsWatchingImmediately() throws {
        recordingCoordinatorSpy = RecordingCoordinatorSpy()
        recordingTrigger = try RecordingTrigger(
            recordingCoordinator: recordingCoordinatorSpy,
            shouldStartWatchingTriggers: true
        )
        XCTAssertEqual(recordingCoordinatorSpy.startRecordingCalledCount, 1)
        XCTAssertEqual(recordingCoordinatorSpy.stopRecordingCalledCount, 0)
        XCTAssertEqual(recordingCoordinatorSpy.captureNextRecordCalledCount, 0)
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
#endif
