/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMSessionSamplerTests: XCTestCase {
    private let measurements = 0..<500

    func testWhenSamplingRateIs0_itAlwaysReturnsNotSampled() {
        // Given
        let sampler = RUMSessionSampler(samplingRate: 0)

        // When
        var notSampledCount = 0
        measurements.forEach { _ in
            notSampledCount += sampler.isSampled() ? 0 : 1
        }

        // Then
        XCTAssertEqual(notSampledCount, measurements.count)
    }

    func testWhenSamplingRateIs100_itAlwaysReturnsIsSampled() {
        // Given
        let sampler = RUMSessionSampler(samplingRate: 100)

        // When
        var isSampledCount = 0
        measurements.forEach { _ in
            isSampledCount += sampler.isSampled() ? 1 : 0
        }

        // Then
        XCTAssertEqual(isSampledCount, measurements.count)
    }

    func testWhenSamplingRateIsLow_itReturnsNotSampledMoreOften() {
        // Given
        let sampler = RUMSessionSampler(samplingRate: .random(in: (0..<30)))

        // When
        var isSampledCount = 0
        var notSampledCount = 0
        measurements.forEach { _ in
            let value = sampler.isSampled()
            isSampledCount += value ? 1 : 0
            notSampledCount += value ? 0 : 1
        }

        // Then
        XCTAssertGreaterThan(notSampledCount, isSampledCount)
    }

    func testWhenSamplingRateIsHigh_itReturnsNotSampledMoreOften() {
        // Given
        let sampler = RUMSessionSampler(samplingRate: .random(in: (70..<100)))

        // When
        var isSampledCount = 0
        var notSampledCount = 0
        measurements.forEach { _ in
            let value = sampler.isSampled()
            isSampledCount += value ? 1 : 0
            notSampledCount += value ? 0 : 1
        }

        // Then
        XCTAssertGreaterThan(isSampledCount, notSampledCount)
    }

    func testWhenInitializing_itSanitizesSamplingRateToAllowedRange() {
        measurements.forEach { _ in
            // Given
            let randomRate: Float = .random(in: -100..<200)

            // When
            let sampler = RUMSessionSampler(samplingRate: randomRate)

            // Then
            XCTAssertGreaterThanOrEqual(sampler.samplingRate, 0)
            XCTAssertLessThanOrEqual(sampler.samplingRate, 100)
        }
    }
}
