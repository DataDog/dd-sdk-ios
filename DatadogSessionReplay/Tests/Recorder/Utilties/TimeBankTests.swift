/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogSessionReplay

class TimeBankTests: XCTestCase {
    func testUntouchedBalance() {
        // Given
        let bank = RecordingTimeBank()

        // When
        bank.recharge(timestamp: .mockRandom())

        // Then
        XCTAssertTrue(bank.isPositive)
    }

    func testConsumeAllBalance() {
        // Given
        let interval: TimeInterval = .mockRandom(min: 0, max: 10)
        let balance = interval / 2
        let bank = RecordingTimeBank(balance: balance, interval: interval)

        // When
        bank.consume(interval: balance)
        bank.consume(interval: balance)

        // Then
        XCTAssertFalse(bank.isPositive)
    }

    func testRecoverBalance() {
        // Given
        let interval: TimeInterval = .mockRandom(min: 0, max: 10)
        let balance = interval / 3
        let initialDate: Date = .mockRandom()

        let bank = RecordingTimeBank(balance: balance, interval: interval)
        bank.recharge(timestamp: initialDate)

        // When
        bank.consume(interval: balance)
        bank.recharge(timestamp: initialDate.addingTimeInterval(interval))
        bank.consume(interval: balance)

        // Then
        XCTAssertTrue(bank.isPositive)
    }

    func testDidNotRecoverBalance() {
        // Given
        let interval: TimeInterval = .mockRandom(min: 0, max: 10)
        let balance = interval / 3
        let initialDate: Date = .mockRandom()

        let bank = RecordingTimeBank(balance: balance, interval: interval)
        bank.recharge(timestamp: initialDate)

        // When
        bank.consume(interval: balance)
        bank.consume(interval: balance)
        bank.recharge(timestamp: initialDate.addingTimeInterval(interval))
        bank.consume(interval: balance)

        // Then
        XCTAssertFalse(bank.isPositive)
    }
}
