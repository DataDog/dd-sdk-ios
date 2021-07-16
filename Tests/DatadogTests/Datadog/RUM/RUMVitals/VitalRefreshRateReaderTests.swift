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
        let registrar_view1 = VitalPublisher(initialValue: VitalInfo())
        let registrar_view2 = VitalPublisher(initialValue: VitalInfo())

        // View1 has simple UI, high FPS expected
        reader.register(registrar_view1)

        // Wait without blocking UI thread
        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertGreaterThan(registrar_view1.currentValue.sampleCount, 0)
            XCTAssertGreaterThan(UIScreen.main.maximumFramesPerSecond, Int(registrar_view1.currentValue.maxValue!))
            XCTAssertGreaterThan(registrar_view1.currentValue.minValue!, 0.0)
        }

        reader.unregister(registrar_view1)

        // View2 has complex UI, lower FPS expected
        reader.register(registrar_view2)

        // Block UI thread
        Thread.sleep(forTimeInterval: 1.0)

        // Wait after blocking UI thread so that reader will read refresh rate before assertions
        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        waitForExpectations(timeout: 0.5) { _ in }

        XCTAssertGreaterThan(registrar_view2.currentValue.sampleCount, 0)
        XCTAssertGreaterThan(registrar_view1.currentValue.meanValue!, registrar_view2.currentValue.meanValue!)
    }

    func testAppStateHandling() {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        let registrar = VitalPublisher(initialValue: VitalInfo())

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        mockNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        reader.register(registrar)

        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in }
        XCTAssertEqual(registrar.currentValue.sampleCount, 0)

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in }
        XCTAssertGreaterThan(registrar.currentValue.sampleCount, 0)
    }
}
