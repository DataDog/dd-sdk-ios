/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
@testable import TestUtilities
@testable import DatadogCore

final class BrightnessLevelSourceTests: XCTestCase {
    private let notificationCenter = MockNotificationCenter()

    func testInitialValue() throws {
        // Given
        let source = BrightnessLevelSource(notificationCenter: notificationCenter)

        // Then
        XCTAssertNotNil(source.initialValue)
        XCTAssertEqual(source.initialValue, Float(UIScreen.main.brightness))
    }

    func testBrightnessChange() async throws {
        // Given
        let mockScreen = UIScreenMock(brightness: 0.2)
        let source = BrightnessLevelSource(notificationCenter: notificationCenter, screen: mockScreen)
        var iterator = source.values.makeAsyncIterator()

        // When
        mockScreen.brightness = 0.5
        notificationCenter.postFakeNotification(name: UIScreen.brightnessDidChangeNotification)

        // Then
        let value = await iterator.next()
        XCTAssertEqual(value, 0.5)
    }
}

#endif
