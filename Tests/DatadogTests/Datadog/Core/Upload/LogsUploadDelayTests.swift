/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadDelayTests: XCTestCase {
    private let mockPerformancePreset: PerformancePreset = .mockWith(
        initialLogsUploadDelay: 3,
        defaultLogsUploadDelay: 5,
        minLogsUploadDelay: 1,
        maxLogsUploadDelay: 20,
        logsUploadDelayDecreaseFactor: 0.9
    )

    func testWhenNotModified_itReturnsInitialDelay() {
        var delay = DataUploadDelay(performance: mockPerformancePreset)
        XCTAssertEqual(delay.nextUploadDelay(), mockPerformancePreset.initialLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), mockPerformancePreset.initialLogsUploadDelay)
    }

    func testWhenDecreasing_itGoesDownToMinimumDelay() {
        var delay = DataUploadDelay(performance: mockPerformancePreset)
        var previousValue: TimeInterval = delay.nextUploadDelay()

        while previousValue != mockPerformancePreset.minLogsUploadDelay {
            delay.decrease()

            let nextValue = delay.nextUploadDelay()
            XCTAssertEqual(
                nextValue / previousValue,
                mockPerformancePreset.logsUploadDelayDecreaseFactor,
                accuracy: 0.1
            )
            XCTAssertLessThanOrEqual(nextValue, max(previousValue, mockPerformancePreset.minLogsUploadDelay))

            previousValue = nextValue
        }
    }

    func testWhenIncreasedOnce_itReturnsMaximumDelayOnceThenGoesBackToDefaultDelay() {
        var delay = DataUploadDelay(performance: mockPerformancePreset)
        delay.decrease()
        delay.increaseOnce()

        XCTAssertEqual(delay.nextUploadDelay(), mockPerformancePreset.maxLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), mockPerformancePreset.defaultLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), mockPerformancePreset.defaultLogsUploadDelay)
    }
}
