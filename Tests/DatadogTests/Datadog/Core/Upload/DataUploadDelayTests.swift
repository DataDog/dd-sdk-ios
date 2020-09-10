/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadDelayTests: XCTestCase {
    private let mockPerformance = UploadPerformanceMock(
        initialUploadDelay: 3,
        defaultUploadDelay: 5,
        minUploadDelay: 1,
        maxUploadDelay: 20,
        uploadDelayChangeRate: 0.1
    )

    func testWhenNotModified_itReturnsInitialDelay() {
        let delay = DataUploadDelay(performance: mockPerformance)
        XCTAssertEqual(delay.nextUploadDelay(), mockPerformance.initialUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), mockPerformance.initialUploadDelay)
    }

    func testWhenDecreasing_itGoesDownToMinimumDelay() {
        var delay = DataUploadDelay(performance: mockPerformance)
        var previousValue: TimeInterval = delay.nextUploadDelay()

        while previousValue > mockPerformance.minUploadDelay {
            delay.decrease()

            let nextValue = delay.nextUploadDelay()
            XCTAssertEqual(
                nextValue / previousValue,
                1.0 - mockPerformance.uploadDelayChangeRate,
                accuracy: 0.1
            )
            XCTAssertLessThanOrEqual(nextValue, max(previousValue, mockPerformance.minUploadDelay))

            previousValue = nextValue
        }
    }

    func testWhenIncreasing_itClampsToMaximumDelay() {
        var delay = DataUploadDelay(performance: mockPerformance)
        var previousValue: TimeInterval = delay.nextUploadDelay()

        while previousValue < mockPerformance.maxUploadDelay {
            delay.increase()

            let nextValue = delay.nextUploadDelay()
            XCTAssertEqual(
                nextValue / previousValue,
                1.0 + mockPerformance.uploadDelayChangeRate,
                accuracy: 0.1
            )
            XCTAssertGreaterThanOrEqual(nextValue, min(previousValue, mockPerformance.maxUploadDelay))
            previousValue = nextValue
        }
    }
}
