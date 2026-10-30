/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
#if os(macOS)
import AppKit
#endif

@testable import DatadogRUM

final class FirstFrameReaderTests: XCTestCase {
    func testFirstFrameIsProcessedCorrectly() {
        let dateProvider = DateProviderMock()
        let reader = FirstFrameReader(dateProvider: DateProviderMock(), mediaTimeProvider: MediaTimeProviderMock(current: 0))
        let rumCommandSubscriber = RUMCommandSubscriberMock()
        reader.publish(to: rumCommandSubscriber)
        let frameInfoProvider = FrameInfoProviderMock(target: self, selector: .noOp)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 2
        frameInfoProvider.nextFrameTimestamp = 4
        reader.didUpdateFrame(link: frameInfoProvider)

        // 2nd frame (should not be taken into account)
        frameInfoProvider.currentFrameTimestamp = 4
        frameInfoProvider.nextFrameTimestamp = 5
        reader.didUpdateFrame(link: frameInfoProvider)

        XCTAssertEqual(
            rumCommandSubscriber.lastReceivedCommand!.time.timeIntervalSince1970,
            dateProvider.now.addingTimeInterval(1).timeIntervalSince1970,
            accuracy: 1e9
        )
    }
}

#if os(macOS)
final class FirstWindowReaderTests: XCTestCase {
    private final class WindowMock: NSWindow {
        var isVisibleMock = true

        override var isVisible: Bool { isVisibleMock }
    }

    private let notificationCenter = NotificationCenter()
    private let subscriber = RUMCommandSubscriberMock()
    private let dateProvider = DateProviderMock(now: .mockDecember15th2019At10AMUTC())

    private lazy var reader = FirstWindowReader(dateProvider: dateProvider, notificationCenter: notificationCenter)

    private func postUpdate(of window: NSWindow) {
        notificationCenter.post(name: NSWindow.didUpdateNotification, object: window)
    }

    func testWhenWindowOnScreenIsUpdated_itReportsTTIDAtThatTime() throws {
        // Given
        reader.publish(to: subscriber)

        // When
        dateProvider.now = .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
        postUpdate(of: WindowMock())

        // Then
        let command = try XCTUnwrap(subscriber.lastReceivedCommand as? RUMTimeToInitialDisplayCommand)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        XCTAssertFalse(reader.isActive)
    }

    func testWhenWindowNotOnScreenIsUpdated_itDoesNotReportTTID() {
        // Given
        reader.publish(to: subscriber)
        let window = WindowMock()
        window.isVisibleMock = false

        // When
        postUpdate(of: window)

        // Then
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        XCTAssertTrue(reader.isActive)
    }

    func testWhenWindowsAreUpdatedSeveralTimes_itReportsTTIDOnlyOnce() {
        // Given
        reader.publish(to: subscriber)

        // When
        postUpdate(of: WindowMock())
        postUpdate(of: WindowMock())

        // Then
        XCTAssertEqual(subscriber.receivedCommands.count, 1)
    }

    func testWhenWindowIsUpdatedBeforePublishing_itIsIgnored() {
        // When
        postUpdate(of: WindowMock())
        reader.publish(to: subscriber)

        // Then
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        XCTAssertTrue(reader.isActive)
    }

    func testWhenStopped_itDoesNotReportTTID() {
        // Given
        reader.publish(to: subscriber)

        // When
        reader.stop()
        postUpdate(of: WindowMock())

        // Then
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
    }
}
#endif
