/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Experimental)
@testable import DatadogRUM

class TimeseriesConfigurationTests: XCTestCase {
    func testAllAvailableOnCurrentPlatform() {
        #if os(watchOS)
        XCTAssertEqual(RUM.Configuration.TimeseriesType.allAvailableOnCurrentPlatform, [.memory], "CPU usage is unavailable on watchOS")
        #else
        XCTAssertEqual(RUM.Configuration.TimeseriesType.allAvailableOnCurrentPlatform, [.memory, .cpu])
        #endif
    }

    func testWhenCollectTypesIsNil_effectiveCollectTypesReturnsAllAvailableOnCurrentPlatform() {
        // Given
        let timeseries = RUM.Configuration.Timeseries()

        // Then
        XCTAssertEqual(timeseries.effectiveCollectTypes, RUM.Configuration.TimeseriesType.allAvailableOnCurrentPlatform)
    }

    func testWhenCollectTypesIsMemory_effectiveCollectTypesIsMemory() {
        // Given
        let timeseries = RUM.Configuration.Timeseries(collectTypes: [.memory])

        // Then
        XCTAssertEqual(timeseries.effectiveCollectTypes, [.memory])
    }

    func testWhenCollectTypesIsCpu_effectiveCollectTypesIsIntersectedWithPlatformAvailability() {
        // Given
        let timeseries = RUM.Configuration.Timeseries(collectTypes: [.cpu])

        // Then
        #if os(watchOS)
        XCTAssertTrue(timeseries.effectiveCollectTypes.isEmpty, "CPU is unavailable on watchOS, so requesting it alone must resolve to an empty selection")
        #else
        XCTAssertEqual(timeseries.effectiveCollectTypes, [.cpu])
        #endif
    }

    func testWhenCollectTypesIsEmpty_effectiveCollectTypesIsEmpty() {
        // Given
        let timeseries = RUM.Configuration.Timeseries(collectTypes: [])

        // Then
        XCTAssertTrue(timeseries.effectiveCollectTypes.isEmpty, "An explicit empty selection must disable collection entirely")
    }

    func testWhenCollectTypesIsBothTypes_effectiveCollectTypesIsIntersectedWithPlatformAvailability() {
        // Given
        let timeseries = RUM.Configuration.Timeseries(collectTypes: [.memory, .cpu])

        // Then
        XCTAssertEqual(timeseries.effectiveCollectTypes, RUM.Configuration.TimeseriesType.allAvailableOnCurrentPlatform)
    }
}
