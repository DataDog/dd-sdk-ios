/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities
@testable import DatadogCore

@MainActor
final class BatteryStatusSourceTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testPublishBatteryState() async throws {
        // Given
        let device = UIDeviceMock(batteryState: .unknown)
        let source = BatteryStatusSource(notificationCenter: notificationCenter, device: device)
        var iterator = source.values.makeAsyncIterator()

        // When
        device.batteryState = .charging
        notificationCenter.post(name: UIDevice.batteryStateDidChangeNotification, object: device)

        // Then
        let value = await iterator.next()
        XCTAssertEqual(value??.state, .charging)
    }

    func testPublishBatteryLevel() async throws {
        // Given
        let device = UIDeviceMock(batteryLevel: 0.5)
        let source = BatteryStatusSource(notificationCenter: notificationCenter, device: device)
        var iterator = source.values.makeAsyncIterator()

        // When
        device.batteryLevel = 0.75
        notificationCenter.post(name: UIDevice.batteryStateDidChangeNotification, object: device)

        // Then
        let value = await iterator.next()
        XCTAssertEqual(value??.level, 0.75)
    }
}

#endif
