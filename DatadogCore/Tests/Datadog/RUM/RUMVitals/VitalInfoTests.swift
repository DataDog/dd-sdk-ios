/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

class VitalInfoTest: XCTestCase {
    func testItUpdatesVitalInfoOnFirstValue() {
        let randomValue = Double.random(in: -65_536.0...65_536.0)
        var testedInfo = VitalInfo()

        XCTAssertEqual(testedInfo.sampleCount, 0)
        XCTAssertNil(testedInfo.minValue)
        XCTAssertNil(testedInfo.maxValue)
        XCTAssertNil(testedInfo.meanValue)
        XCTAssertNil(testedInfo.greatestDiff)

        // When
        testedInfo.addSample(randomValue)

        // Then
        XCTAssertEqual(testedInfo.minValue, randomValue)
        XCTAssertEqual(testedInfo.maxValue, randomValue)
        XCTAssertEqual(testedInfo.meanValue, randomValue)
        XCTAssertEqual(testedInfo.sampleCount, 1)
        XCTAssertEqual(testedInfo.greatestDiff, 0)
    }

    func testItUpdatesVitalInfoOnMultipleValue() {
        let randomValues = (0..<3).map { _ in Double.random(in: -65_536.0...65_536.0) }
        var testedInfo = VitalInfo()

        // When
        testedInfo.addSample(randomValues[0])
        // Then
        XCTAssertEqual(testedInfo.minValue, randomValues[0])
        XCTAssertEqual(testedInfo.maxValue, randomValues[0])
        XCTAssertEqual(testedInfo.meanValue, randomValues[0])
        XCTAssertEqual(testedInfo.sampleCount, 1)
        XCTAssertEqual(testedInfo.greatestDiff, 0)

        // When
        testedInfo.addSample(randomValues[1])
        // Then
        XCTAssertEqual(testedInfo.minValue, randomValues[0...1].min())
        XCTAssertEqual(testedInfo.maxValue, randomValues[0...1].max())
        XCTAssertEqual(testedInfo.meanValue, randomValues[0...1].reduce(0, +) / 2.0)
        XCTAssertEqual(testedInfo.sampleCount, 2)
        XCTAssertEqual(testedInfo.greatestDiff, randomValues[0...1].max()! - randomValues[0...1].min()!)

        // When
        testedInfo.addSample(randomValues[2])
        // Then
        XCTAssertEqual(testedInfo.minValue, randomValues[0...2].min())
        XCTAssertEqual(testedInfo.maxValue, randomValues[0...2].max())
        XCTAssertEqual(testedInfo.meanValue, randomValues[0...2].reduce(0, +) / 3.0)
        XCTAssertEqual(testedInfo.sampleCount, 3)
        XCTAssertEqual(testedInfo.greatestDiff, randomValues[0...2].max()! - randomValues[0...2].min()!)
    }

    func testItScalesDown() {
        let randomValue = Double.random(in: -65_536.0...65_536.0)
        var randomInfo = VitalInfo()
        randomInfo.addSample(randomValue)

        // When
        let testedInfo = randomInfo.scaledDown(by: 2.0)

        // Then
        XCTAssertEqual(testedInfo.minValue, randomValue / 2.0)
        XCTAssertEqual(testedInfo.maxValue, randomValue / 2.0)
        XCTAssertEqual(testedInfo.meanValue, randomValue / 2.0)
        XCTAssertEqual(testedInfo.sampleCount, 1)
        XCTAssertEqual(testedInfo.greatestDiff, 0)
    }
}
