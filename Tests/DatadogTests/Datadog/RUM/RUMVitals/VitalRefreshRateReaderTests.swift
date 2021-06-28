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

    func testHighAndLowRefreshRates() {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        let observer_view1 = VitalObserver(listener: VitalListenerMock())
        let observer_view2 = VitalObserver(listener: VitalListenerMock())

        // View1 has simple UI, high FPS expected
        reader.register(observer_view1)

        // Wait without blocking UI thread
        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertGreaterThan(observer_view1.vitalInfo.sampleCount, 0)
            XCTAssertGreaterThan(UIScreen.main.maximumFramesPerSecond, Int(observer_view1.vitalInfo.maxValue))
            XCTAssertGreaterThan(observer_view1.vitalInfo.minValue, 0.0)
        }

        reader.unregister(observer_view1)

        // View2 has complex UI, lower FPS expected
        reader.register(observer_view2)

        // Block UI thread
        Thread.sleep(forTimeInterval: 1.0)

        // Wait after blocking UI thread so that reader will read refresh rate before assertions
        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        waitForExpectations(timeout: 0.5) { _ in }

        XCTAssertGreaterThan(observer_view2.vitalInfo.sampleCount, 0)
        XCTAssertGreaterThan(observer_view1.vitalInfo.meanValue, observer_view2.vitalInfo.meanValue)
    }

    func testAppStateHandling() {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        let observer = VitalObserver(listener: VitalListenerMock())

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        mockNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        reader.register(observer)

        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in }
        XCTAssertEqual(observer.vitalInfo.sampleCount, 0)

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in }
        XCTAssertGreaterThan(observer.vitalInfo.sampleCount, 0)
    }
}
