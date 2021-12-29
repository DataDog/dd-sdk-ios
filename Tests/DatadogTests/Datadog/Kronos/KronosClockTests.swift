/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import XCTest
@testable import Datadog

final class KronosClockTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KronosClock.reset()
    }

    func testFirst() {
        let expectation = self.expectation(description: "Clock sync calls first closure")
        KronosClock.sync(first: { date, _ in
            XCTAssertNotNil(date)
            expectation.fulfill()
        })

        self.waitForExpectations(timeout: 2)
    }

    func testLast() {
        let expectation = self.expectation(description: "Clock sync calls last closure")
        KronosClock.sync(completion: { date, offset in
            XCTAssertNotNil(date)
            XCTAssertNotNil(offset)
            expectation.fulfill()
        })

        self.waitForExpectations(timeout: 20)
    }

    func testBoth() {
        let firstExpectation = self.expectation(description: "Clock sync calls first closure")
        let lastExpectation = self.expectation(description: "Clock sync calls last closure")
        KronosClock.sync(
            first: { _, _ in
                firstExpectation.fulfill()
            },
            completion: { _, _ in
                lastExpectation.fulfill()
            }
        )

        self.waitForExpectations(timeout: 20)
    }
}
