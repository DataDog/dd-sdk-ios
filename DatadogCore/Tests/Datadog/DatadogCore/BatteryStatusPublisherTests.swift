/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities
@testable import DatadogCore

final class BatteryStatusPublisherTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testPublishBatteryState() throws {
        let expectation = self.expectation(description: "publish battery state")

        // Given
        let device = UIDeviceMock(batteryState: .unknown)

        let publisher = BatteryStatusPublisher(device: device, notificationCenter: notificationCenter)
        publisher.publish { status in
            // Then
            XCTAssertEqual(status?.state, .charging)
            expectation.fulfill()
        }

        // When
        device.batteryState = .charging
        notificationCenter.post(name: UIDevice.batteryStateDidChangeNotification, object: device)
        wait(for: [expectation], timeout: 0.1)
    }

    func testPublishBatteryLevel() throws {
        let expectation = self.expectation(description: "publish battery level")

        // Given
        let device = UIDeviceMock(batteryLevel: 0.5)

        let publisher = BatteryStatusPublisher(device: device, notificationCenter: notificationCenter)
        publisher.publish { status in
            // Then
            XCTAssertEqual(status?.level, 0.75)
            expectation.fulfill()
        }

        // When
        device.batteryLevel = 0.75
        notificationCenter.post(name: UIDevice.batteryStateDidChangeNotification, object: device)
        wait(for: [expectation], timeout: 0.1)
    }
}

#endif
