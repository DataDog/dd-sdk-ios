/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class TimeIntervalExtensionTests: XCTestCase {
    func testTimeIntervalFromMilliseconds() {
        let milliseconds: Int64 = 1_576_404_000_000

        let timeInterval = TimeInterval(fromMilliseconds: milliseconds)
        let date = Date(timeIntervalSince1970: timeInterval)
        XCTAssertEqual(date, Date.mockDecember15th2019At10AMUTC())
    }

    func testTimeIntervalSince1970InMilliseconds() {
        let date15Dec2019 = Date.mockDecember15th2019At10AMUTC()
        XCTAssertEqual(date15Dec2019.timeIntervalSince1970.toMilliseconds, 1_576_404_000_000)

        let dateAdvanced = date15Dec2019 + 9.999
        XCTAssertEqual(dateAdvanced.timeIntervalSince1970.toMilliseconds, 1_576_404_009_999)

        let dateAgo = date15Dec2019 - 0.001
        XCTAssertEqual(dateAgo.timeIntervalSince1970.toMilliseconds, 1_576_403_999_999)

        let overflownDate = Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)
        XCTAssertEqual(overflownDate.timeIntervalSince1970.toMilliseconds, UInt64.max)

        let uInt64MaxDate = Date(timeIntervalSinceReferenceDate: TimeInterval(UInt64.max))
        XCTAssertEqual(uInt64MaxDate.timeIntervalSince1970.toMilliseconds, UInt64.max)
    }

    func testTimeIntervalSince1970InNanoseconds() {
        let date15Dec2019 = Date.mockDecember15th2019At10AMUTC()
        XCTAssertEqual(date15Dec2019.timeIntervalSince1970.toNanoseconds, 1_576_404_000_000_000_000)

        // As `TimeInterval` yields sub-millisecond precision this rounds up to the nearest millisecond:
        let dateAdvanced = date15Dec2019 + 9.999999999
        XCTAssertEqual(dateAdvanced.timeIntervalSince1970.toNanoseconds, 1_576_404_010_000_000_000)

        // As `TimeInterval` yields sub-millisecond precision this rounds up to the nearest millisecond:
        let dateAgo = date15Dec2019 - 0.000000001
        XCTAssertEqual(dateAgo.timeIntervalSince1970.toNanoseconds, 1_576_404_000_000_000_000)

        let overflownDate = Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)
        XCTAssertEqual(overflownDate.timeIntervalSince1970.toNanoseconds, UInt64.max)

        let uInt64MaxDate = Date(timeIntervalSinceReferenceDate: TimeInterval(UInt64.max))
        XCTAssertEqual(uInt64MaxDate.timeIntervalSince1970.toNanoseconds, UInt64.max)
    }
}

class UUIDExtensionTests: XCTestCase {
    func testNullUUID() {
        let uuid: UUID = .nullUUID
        XCTAssertEqual(uuid.uuidString, "00000000-0000-0000-0000-000000000000", "It must be all zeroes")
    }
}

class IntegerOverflowExtensionTests: XCTestCase {
    func testHappyPath() {
        let reasonableDouble = Double(1_000.123456)

        XCTAssertNoThrow(try UInt64(withReportingOverflow: reasonableDouble))
        XCTAssertEqual(try UInt64(withReportingOverflow: reasonableDouble), 1_000)
    }

    func testNegative() {
        let negativeDouble = Double(-1_000.123456)

        XCTAssertThrowsError(try UInt64(withReportingOverflow: negativeDouble)) { error in
            XCTAssertTrue(error is FixedWidthIntegerError<Double>)
            if case let FixedWidthIntegerError.overflow(overflowingValue) = (error as! FixedWidthIntegerError<Double>) {
                XCTAssertEqual(overflowingValue, negativeDouble)
            }
        }
    }

    func testFloat() {
        let simpleFloat = Float(222.123456)

        XCTAssertNoThrow(try UInt8(withReportingOverflow: simpleFloat))
        XCTAssertEqual(try UInt8(withReportingOverflow: simpleFloat), 222)
    }

    func testGreatestFiniteMagnitude() {
        let almostInfinity = Double.greatestFiniteMagnitude

        XCTAssertThrowsError(try UInt64(withReportingOverflow: almostInfinity)) { error in
            XCTAssertTrue(error is FixedWidthIntegerError<Double>)
        }
    }

    func testInfinity() {
        let infinityAndBeyond = Double.infinity

        XCTAssertThrowsError(try UInt64(withReportingOverflow: infinityAndBeyond)) { error in
            XCTAssertTrue(error is FixedWidthIntegerError<Double>)
        }
    }

    func testCornerCase() {
        let uInt64Max = Double(UInt64.max)

        XCTAssertThrowsError(try UInt64(withReportingOverflow: uInt64Max)) { error in
            XCTAssertTrue(error is FixedWidthIntegerError<Double>)
            if case let FixedWidthIntegerError.overflow(overflowingValue) = (error as! FixedWidthIntegerError<Double>) {
                XCTAssertEqual(overflowingValue, uInt64Max)
            }
        }
    }
}

class DoubleExtensionTests: XCTestCase {
    func testDivideIfNotZero() {
        XCTAssertNil(2.0.divideIfNotZero(by: 0))
        XCTAssertEqual(2.0.divideIfNotZero(by: 1.0), 2.0)
    }

    func testInverted() {
        XCTAssertEqual(0.0.inverted, 0.0)
        XCTAssertEqual(2.0.inverted, 0.5)
    }
}
