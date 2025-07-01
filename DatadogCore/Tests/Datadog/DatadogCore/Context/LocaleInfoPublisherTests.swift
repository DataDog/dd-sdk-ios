/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogCore

class LocaleInfoPublisherTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testInitialValueFormatting() throws {
        // Given
        let initialLocale = LocaleInfo(
            locales: ["en-US"],
            currentLocale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "GMT")!
        )

        // Then
        XCTAssertEqual(initialLocale.locales, ["en-US"])
        XCTAssertEqual(initialLocale.currentLocale, "en-US")
        XCTAssertEqual(initialLocale.timeZoneIdentifier, "GMT")
    }

    func testPublishLocaleInfoOnNotification() throws {
        let expectation = self.expectation(description: "Locale info published")
        expectation.expectedFulfillmentCount = 2

        // Given
        let initialLocale = LocaleInfo(
            locales: ["en-US"],
            currentLocale: Locale(identifier: "en-US"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let publisher = LocaleInfoPublisher(initialLocale: initialLocale, notificationCenter: notificationCenter)

        var receivedLocaleInfos: [LocaleInfo] = []

        // When
        publisher.publish { locale in
            receivedLocaleInfos.append(locale)
            expectation.fulfill()
        }

        // First notification should trigger the receiver
        notificationCenter.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        // Second notification should also trigger the receiver
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.notificationCenter.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        }

        waitForExpectations(timeout: 2.0)

        // Then
        XCTAssertEqual(receivedLocaleInfos.count, 2)

        for localeInfo in receivedLocaleInfos {
            XCTAssertEqual(localeInfo.locales, Locale.preferredLanguages)
            XCTAssertEqual(localeInfo.currentLocale, Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
            XCTAssertEqual(localeInfo.timeZoneIdentifier, TimeZone.current.identifier)
        }

        publisher.cancel()
    }
}
