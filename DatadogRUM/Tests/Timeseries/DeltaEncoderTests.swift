/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class DeltaEncoderTests: XCTestCase {
    // MARK: - Memory encoding

    func testEncodeMemory_returnsNilForEmptyBatch() {
        XCTAssertNil(DeltaEncoder.encodeMemory([]))
    }

    func testEncodeMemory_returnsNilForSingleSample() {
        let sample = RUMTimeseriesMemoryEvent.Timeseries.Data(
            dataPoint: .init(memoryMax: 100.0, memoryPercent: 10.0),
            timestamp: 1_000_000_000
        )
        XCTAssertNil(DeltaEncoder.encodeMemory([sample]))
    }

    func testEncodeMemory_correctDeltaEncoding() {
        // Given
        let samples: [RUMTimeseriesMemoryEvent.Timeseries.Data] = [
            .init(dataPoint: .init(memoryMax: 100.0, memoryPercent: 10.0), timestamp: 1_000_000_000),
            .init(dataPoint: .init(memoryMax: 200.5, memoryPercent: 20.0), timestamp: 2_000_000_000),
            .init(dataPoint: .init(memoryMax: 200.5, memoryPercent: 20.5), timestamp: 3_000_000_000)
        ]

        // When
        let result = try! XCTUnwrap(DeltaEncoder.encodeMemory(samples))

        // Then
        XCTAssertEqual(result["precision"] as? Int, 4)

        let ts = try! XCTUnwrap(result["ts"] as? [Int64])
        XCTAssertEqual(ts, [1_000_000_000, 1_000_000_000, 1_000_000_000])

        // memory_max: 100*10000=1_000_000, (200.5-100)*10000=1_005_000, 0
        let memoryMax = try! XCTUnwrap(result["memory_max"] as? [Int64])
        XCTAssertEqual(memoryMax, [1_000_000, 1_005_000, 0])

        // memory_percent: 10*10000=100_000, (20-10)*10000=100_000, (20.5-20)*10000=5_000
        let memoryPercent = try! XCTUnwrap(result["memory_percent"] as? [Int64])
        XCTAssertEqual(memoryPercent, [100_000, 100_000, 5_000])
    }

    // MARK: - CPU encoding

    func testEncodeCPU_returnsNilForEmptyBatch() {
        XCTAssertNil(DeltaEncoder.encodeCPU([]))
    }

    func testEncodeCPU_returnsNilForSingleSample() {
        let sample = RUMTimeseriesCpuEvent.Timeseries.Data(
            dataPoint: .init(cpuUsage: 42.5),
            timestamp: 1_000_000_000
        )
        XCTAssertNil(DeltaEncoder.encodeCPU([sample]))
    }

    func testEncodeCPU_correctDeltaEncoding() {
        // Given
        let samples: [RUMTimeseriesCpuEvent.Timeseries.Data] = [
            .init(dataPoint: .init(cpuUsage: 42.5), timestamp: 1_000_000_000),
            .init(dataPoint: .init(cpuUsage: 43.0), timestamp: 2_000_000_000),
            .init(dataPoint: .init(cpuUsage: 42.0), timestamp: 3_000_000_000)
        ]

        // When
        let result = try! XCTUnwrap(DeltaEncoder.encodeCPU(samples))

        // Then
        XCTAssertEqual(result["precision"] as? Int, 4)

        let ts = try! XCTUnwrap(result["ts"] as? [Int64])
        XCTAssertEqual(ts, [1_000_000_000, 1_000_000_000, 1_000_000_000])

        // value: 42.5*10000=425_000, (43.0-42.5)*10000=5_000, (42.0-43.0)*10000=-10_000
        let cpuUsage = try! XCTUnwrap(result["value"] as? [Int64])
        XCTAssertEqual(cpuUsage, [425_000, 5_000, -10_000])
    }
}
