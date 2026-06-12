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
            dataPoint: .init(memoryFootprint: 100.0, memoryPercent: 10.0),
            timestamp: 1_000_000_000
        )
        XCTAssertNil(DeltaEncoder.encodeMemory([sample]))
    }

    func testEncodeMemory_correctDeltaEncoding() throws {
        // Given
        let samples: [RUMTimeseriesMemoryEvent.Timeseries.Data] = [
            .init(dataPoint: .init(memoryFootprint: 100.0, memoryPercent: 10.0), timestamp: 1_000_000_000),
            .init(dataPoint: .init(memoryFootprint: 200.5, memoryPercent: 20.0), timestamp: 2_000_000_000),
            .init(dataPoint: .init(memoryFootprint: 200.5, memoryPercent: 20.5), timestamp: 3_000_000_000)
        ]

        // When
        let result = try XCTUnwrap(DeltaEncoder.encodeMemory(samples))

        // Then
        XCTAssertEqual(result["precision"] as? Int, 4)
        XCTAssertEqual(result["resolution"] as? String, "ns")

        let ts = try XCTUnwrap(result["ts"] as? [Int64])
        XCTAssertEqual(ts, [1_000_000_000, 1_000_000_000, 1_000_000_000])

        // memory_footprint: 100*10000=1_000_000, (200.5-100)*10000=1_005_000, 0
        let memoryFootprint = try XCTUnwrap(result["memory_footprint"] as? [Int64])
        XCTAssertEqual(memoryFootprint, [1_000_000, 1_005_000, 0])

        // memory_percent: 10*10000=100_000, (20-10)*10000=100_000, (20.5-20)*10000=5_000
        let memoryPercent = try XCTUnwrap(result["memory_percent"] as? [Int64])
        XCTAssertEqual(memoryPercent, [100_000, 100_000, 5_000])
    }

    func testEncodeMemory_doesNotCrashOnOverflowBoundaryValues() throws {
        // Values scaled to near Int64.max / Int64.min to exercise subtractingReportingOverflow
        let hugeBytes = Double(Int64.max) / 10_000.0
        let samples: [RUMTimeseriesMemoryEvent.Timeseries.Data] = [
            .init(dataPoint: .init(memoryFootprint: hugeBytes, memoryPercent: 100.0), timestamp: Int64.max),
            .init(dataPoint: .init(memoryFootprint: 0.0, memoryPercent: 0.0), timestamp: 0)
        ]
        // Should not crash
        let result = try XCTUnwrap(DeltaEncoder.encodeMemory(samples))
        XCTAssertNotNil(result["memory_footprint"] as? [Int64])
    }

    // MARK: - CPU encoding

    func testEncodeCPU_doesNotCrashOnOverflowBoundaryValues() throws {
        let hugeCPU = Double(Int64.max) / 10_000.0
        let samples: [RUMTimeseriesCpuEvent.Timeseries.Data] = [
            .init(dataPoint: .init(cpuUsage: hugeCPU), timestamp: Int64.max),
            .init(dataPoint: .init(cpuUsage: 0.0), timestamp: 0)
        ]
        // Should not crash
        let result = try XCTUnwrap(DeltaEncoder.encodeCPU(samples))
        XCTAssertNotNil(result["value"] as? [Int64])
    }

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

    func testEncodeCPU_correctDeltaEncoding() throws {
        // Given
        let samples: [RUMTimeseriesCpuEvent.Timeseries.Data] = [
            .init(dataPoint: .init(cpuUsage: 42.5), timestamp: 1_000_000_000),
            .init(dataPoint: .init(cpuUsage: 43.0), timestamp: 2_000_000_000),
            .init(dataPoint: .init(cpuUsage: 42.0), timestamp: 3_000_000_000)
        ]

        // When
        let result = try XCTUnwrap(DeltaEncoder.encodeCPU(samples))

        // Then
        XCTAssertEqual(result["precision"] as? Int, 4)
        XCTAssertEqual(result["resolution"] as? String, "ns")

        let ts = try XCTUnwrap(result["ts"] as? [Int64])
        XCTAssertEqual(ts, [1_000_000_000, 1_000_000_000, 1_000_000_000])

        // value: 42.5*10000=425_000, (43.0-42.5)*10000=5_000, (42.0-43.0)*10000=-10_000
        let cpuUsage = try XCTUnwrap(result["value"] as? [Int64])
        XCTAssertEqual(cpuUsage, [425_000, 5_000, -10_000])
    }
}
