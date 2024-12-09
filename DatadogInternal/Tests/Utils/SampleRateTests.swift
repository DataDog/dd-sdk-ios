/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

final class SampleRateTests: XCTestCase {
    func testPercentageProportion() {
        // Given
        let zeroSampleRate: SampleRate = 0.0
        let sampleRate: SampleRate = 50.0
        let fullSampleRate: SampleRate = 100.0

        // Then
        XCTAssertEqual(zeroSampleRate.percentageProportion, 0.0)
        XCTAssertEqual(sampleRate.percentageProportion, 0.5)
        XCTAssertEqual(fullSampleRate.percentageProportion, 1.0)
    }

    func testComposedSampleRate() {
        // Given
        let sampleRate1: SampleRate = 20.0
        let sampleRate2: SampleRate = 15.0

        // When
        let composedRate = sampleRate1.composed(with: sampleRate2)
        let composedRateInverted = sampleRate2.composed(with: sampleRate1)
        let composedRateWithFullSampleRate = sampleRate1.composed(with: .maxSampleRate)

        // Then
        XCTAssertEqual(composedRate, 3.0)
        XCTAssertEqual(composedRateInverted, 3.0)
        XCTAssertEqual(composedRateWithFullSampleRate, sampleRate1)
    }

    func testComposedSampleRateWithZeroSampleRate() {
        // Given
        let sampleRate1: SampleRate = 0.0
        let sampleRate2: SampleRate = 15.0

        // When
        let composedRate = sampleRate1.composed(with: sampleRate2)
        let composedRateInverted = sampleRate2.composed(with: sampleRate1)

        // Then
        XCTAssertEqual(composedRate, 0.0)
        XCTAssertEqual(composedRateInverted, 0.0)
    }

    func testComposedSampleRateWithFullSampleRate() {
        // Given
        let sampleRate1: SampleRate = .maxSampleRate
        let sampleRate2: SampleRate = .maxSampleRate

        // When
        let composedRate = sampleRate1.composed(with: sampleRate2)
        let composedRateInverted = sampleRate2.composed(with: sampleRate1)

        // Then
        XCTAssertEqual(composedRate, .maxSampleRate)
        XCTAssertEqual(composedRateInverted, .maxSampleRate)
    }

    func testComposedSampleWithMultipleSampleRates() {
        // Given
        let sampleRate1: SampleRate = .maxSampleRate
        let sampleRate2: SampleRate = 50.0
        let sampleRate3: SampleRate = 20.0
        let sampleRate4: SampleRate = 15.0

        // When
        let composedRateWith3Layers = sampleRate1.composed(with: sampleRate2).composed(with: sampleRate3)
        let composedRateWith4Layers = sampleRate1.composed(with: sampleRate2).composed(with: sampleRate3).composed(with: sampleRate4)

        // Then
        XCTAssertEqual(composedRateWith3Layers, 10.0)
        XCTAssertEqual(composedRateWith4Layers, 1.5)
    }
}
