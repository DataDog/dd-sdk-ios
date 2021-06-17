/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class VitalRefreshRateReaderTests: XCTestCase {
    private let mockNotificationCenter = NotificationCenter()

    func testRefreshRateReader() throws {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        XCTAssertFalse(reader.isRunning)

        let observer_view1 = VitalObserver(listener: VitalListenerMock())
        let observer_view2 = VitalObserver(listener: VitalListenerMock())

        XCTAssertNoThrow(try reader.start())
        XCTAssertTrue(reader.isRunning)

        reader.register(observer_view1)

        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.0)
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 3.0) { _ in
            XCTAssertGreaterThan(observer_view1.vitalInfo.sampleCount, 0)
            XCTAssertGreaterThan(UIScreen.main.maximumFramesPerSecond, Int(observer_view1.vitalInfo.maxValue))
            XCTAssertGreaterThan(observer_view1.vitalInfo.minValue, 0.0)
        }

        reader.register(observer_view1)

        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.0)
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 3.0) { _ in
            XCTAssertGreaterThan(observer_view1.vitalInfo.sampleCount, observer_view2.vitalInfo.sampleCount)
        }
    }

    func testAppStateHandling() throws {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        XCTAssertFalse(reader.isRunning)

        let observer = VitalObserver(listener: VitalListenerMock())

        XCTAssertNoThrow(try reader.start())
        XCTAssertTrue(reader.isRunning)

        mockNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        reader.register(observer)

        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.0)
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 3.0) { _ in
            XCTAssertEqual(observer.vitalInfo.sampleCount, 0)
        }

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.0)
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 3.0) { _ in
            XCTAssertGreaterThan(observer.vitalInfo.sampleCount, 0)
        }
    }

    func testReaderNotRestartIfNotAlreadyRunning() throws {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        XCTAssertFalse(reader.isRunning)

        let observer = VitalObserver(listener: VitalListenerMock())

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let expectation1 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.0)
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 3.0) { _ in
            XCTAssertEqual(observer.vitalInfo.sampleCount, 0)
        }
    }
}
