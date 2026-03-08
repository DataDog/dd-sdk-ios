/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogCore

class LocaleInfoSourceTests: XCTestCase {
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

    func testPublishLocaleInfoOnNotification() async throws {
        // Given
        let initialLocale = LocaleInfo(
            locales: ["en-US"],
            currentLocale: Locale(identifier: "en-US"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let source = LocaleInfoSource(initialLocale: initialLocale, notificationCenter: notificationCenter)
        var iterator = source.values.makeAsyncIterator()

        // When
        notificationCenter.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        // Then
        let localeInfo = await iterator.next()
        XCTAssertNotNil(localeInfo)
        XCTAssertEqual(localeInfo?.locales, Locale.preferredLanguages)
        XCTAssertEqual(localeInfo?.currentLocale, Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        XCTAssertEqual(localeInfo?.timeZoneIdentifier, TimeZone.current.identifier)
    }
}
