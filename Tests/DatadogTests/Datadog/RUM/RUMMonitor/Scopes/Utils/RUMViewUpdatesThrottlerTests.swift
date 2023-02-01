/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMViewUpdatesThrottlerTests: XCTestCase {
    private let randomViewUpdateThreshold: TimeInterval = .mockRandom(min: 1, max: 10)
    private lazy var throttler = RUMViewUpdatesThrottler(viewUpdateThreshold: randomViewUpdateThreshold)

    func testItAcceptsTheFirstEvent() {
        XCTAssertTrue(throttler.accept(event: .mockRandom()))
    }

    func testItAcceptsTheLastEvent() {
        XCTAssertTrue(throttler.accept(event: .mockRandomWith(viewIsActive: false)))
    }

    func testItRejectsNextEventWhenItArrivesEarlierThanThreshold() {
        let firstEvent: RUMViewEvent = .mockRandomWith(
            viewIsActive: true, // not a final event
            viewTimeSpent: 0,
            crashCount: 0
        )
        let nextEvent: RUMViewEvent = .mockRandomWith(
            viewIsActive: true, // not a final event
            viewTimeSpent: randomViewUpdateThreshold.toInt64Nanoseconds - 1,
            crashCount: 0
        )

        XCTAssertTrue(throttler.accept(event: firstEvent), "It should always accepts first event")
        XCTAssertFalse(throttler.accept(event: nextEvent), "It should reject next event as it arrived earlier than threshold")
    }

    func testItAcceptsNextEventWhenItArrivesLaterThanThreshold() {
        let firstEvent: RUMViewEvent = .mockRandomWith(
            viewIsActive: true, // not a final event
            viewTimeSpent: 0,
            crashCount: 0
        )
        let nextEvent: RUMViewEvent = .mockRandomWith(
            viewIsActive: true, // not a final event
            viewTimeSpent: randomViewUpdateThreshold.toInt64Nanoseconds + 1,
            crashCount: 0
        )

        XCTAssertTrue(throttler.accept(event: firstEvent), "It should always accepts first event")
        XCTAssertTrue(throttler.accept(event: nextEvent), "It should accept next event as it arrived later than threshold")
    }
}
