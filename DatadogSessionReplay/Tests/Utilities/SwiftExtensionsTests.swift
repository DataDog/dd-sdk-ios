/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@testable import DatadogSessionReplay

class FixedWidthIntegerTests: XCTestCase {
    func testWhenConvertingWithNoOverflow_itPreservesTheValue() {
        // Given
        let floatingValue = CGFloat(Int.mockRandom(min: .min, max: .max))

        // When
        let convertedValue = Int(withNoOverflow: floatingValue)

        // Then
        let recoveredFloatingValue = CGFloat(convertedValue)
        XCTAssertEqual(recoveredFloatingValue, floatingValue)
    }

    func testWhenConvertingWithMaxOverflow_itCapsTheValue() {
        // Given
        let floatingValue: CGFloat = .greatestFiniteMagnitude

        // When
        let convertedValue = Int(withNoOverflow: floatingValue)

        // Then
        let expectedConvertedValue = Int.max
        XCTAssertEqual(expectedConvertedValue, convertedValue)
    }

    func testWhenConvertingWithMinOverflow_itCapsTheValue() {
        // Given
        let floatingValue: CGFloat = -.greatestFiniteMagnitude

        // When
        let convertedValue = Int(withNoOverflow: floatingValue)

        // Then
        let expectedConvertedValue = Int.min
        XCTAssertEqual(expectedConvertedValue, convertedValue)
    }
}

class TimeIntervalTests: XCTestCase {
    func testWhenConvertingPresentIntervalsToInt64Milliseconds_itGivesPreciseValue() {
        let date15Dec2019 = Date.mockDecember15th2019At10AMUTC()
        XCTAssertEqual(date15Dec2019.timeIntervalSince1970.toInt64Milliseconds, 1_576_404_000_000)

        let dateIn2050 = Date.mockSpecificUTCGregorianDate(year: 2_050, month: 08, day: 12, hour: 12)
        XCTAssertEqual(dateIn2050.timeIntervalSince1970.toInt64Milliseconds, 2_543_918_400_000)

        let dateIn1970 = Date.mockSpecificUTCGregorianDate(year: 1_970, month: 08, day: 12, hour: 12)
        XCTAssertEqual(dateIn1970.timeIntervalSince1970.toInt64Milliseconds, 19_310_400_000)
    }

    func testWhenConvertingDistantIntervalToInt64Milliseconds_itCapsTheValue() {
        let overflownDate = Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)
        XCTAssertEqual(overflownDate.timeIntervalSince1970.toInt64Milliseconds, Int64.max)

        let uInt64MaxDate = Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude)
        XCTAssertEqual(uInt64MaxDate.timeIntervalSince1970.toInt64Milliseconds, Int64.min)
    }
}
