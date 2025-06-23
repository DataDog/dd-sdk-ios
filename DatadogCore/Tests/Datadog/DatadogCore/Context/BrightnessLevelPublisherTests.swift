/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
@testable import TestUtilities
@testable import DatadogCore

final class BrightnessLevelPublisherTests: XCTestCase {
    private let notificationCenter = MockNotificationCenter()

    func testInitialValue() throws {
        // Given
        let publisher = BrightnessLevelPublisher(notificationCenter: notificationCenter)

        // Then
        XCTAssertNotNil(publisher.initialValue)
        XCTAssertEqual(publisher.initialValue, Float(UIScreen.main.brightness))
    }

    func testMultipleBrightnessChanges() throws {
        let expectation1 = self.expectation(description: "first brightness change")
        let expectation2 = self.expectation(description: "second brightness change")

        // Given
        let mockScreen = UIScreenMock(brightness: 0.2)
        let publisher = BrightnessLevelPublisher(notificationCenter: notificationCenter, screen: mockScreen)
        var receivedValues: [Float] = []

        publisher.publish { level in
            if let level = level {
                receivedValues.append(level)

                switch receivedValues.count {
                case 1:
                    expectation1.fulfill()
                case 2:
                    expectation2.fulfill()
                default:
                    break
                }
            }
        }

        // When
        mockScreen.brightness = 0.5
        notificationCenter.postFakeNotification(name: UIScreen.brightnessDidChangeNotification)
        mockScreen.brightness = 0.8
        notificationCenter.postFakeNotification(name: UIScreen.brightnessDidChangeNotification)

        wait(for: [expectation1, expectation2], timeout: 0.1)

        // Then
        XCTAssertEqual(receivedValues.count, 3)
        XCTAssertEqual(receivedValues[0], 0.2)
        XCTAssertEqual(receivedValues[1], 0.5)
        XCTAssertEqual(receivedValues[2], 0.8)
    }
}

#endif
