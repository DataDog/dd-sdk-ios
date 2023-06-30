/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

private class Allocation {
    fileprivate let numberOfBytes: Int
    private var pointer: UnsafeMutablePointer<UInt8>! // swiftlint:disable:this implicitly_unwrapped_optional

    init(numberOfBytes: Int) {
        self.numberOfBytes = numberOfBytes
    }

    func allocate() {
        pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: numberOfBytes)
        pointer.initialize(repeating: 0, count: numberOfBytes)
    }

    func deallocate() {
        pointer.deallocate()
    }
}

internal class VitalMemoryReaderTest: XCTestCase {
    private let allocation = Allocation(
        numberOfBytes: 8 * 1_024 * 1_024 // 8MB is significantly more than any other allocation in tests process
    )

    func testReadMemory() throws {
        let reader = VitalMemoryReader()
        let result = reader.readVitalData()
        XCTAssertNotNil(result)
    }

    func testWhenMemoryConsumptionGrows() throws {
        // Given
        let reader = VitalMemoryReader()

        // When
        var deltas: [Double] = []

        try (0..<20).forEach { _ in // measure mean value to mitigate flakiness
            let before = try XCTUnwrap(reader.readVitalData())
            allocation.allocate()
            let after = try XCTUnwrap(reader.readVitalData())
            allocation.deallocate()
            deltas.append(after - before)
        }

        // Then
        let meanDelta = deltas.reduce(0.0, +) / Double(deltas.count)
        let expectedMeanDelta = Double(allocation.numberOfBytes) * 0.6 // only 60% to mitigate external deallocations in the process

        XCTAssertGreaterThan(
            meanDelta,
            expectedMeanDelta,
            "Mean delta \(toMB(meanDelta))MB is not greater than \(toMB(expectedMeanDelta))MB"
        )
    }

    func testWhenMemoryConsumptionShrinks() throws {
        // Given
        let reader = VitalMemoryReader()

        // When
        var deltas: [Double] = []

        try (0..<20).forEach { _ in // measure mean value to mitigate flakiness
            allocation.allocate()
            let before = try XCTUnwrap(reader.readVitalData())
            allocation.deallocate()
            let after = try XCTUnwrap(reader.readVitalData())
            deltas.append(after - before)
        }

        // Then
        let meanDelta = deltas.reduce(0.0, +) / Double(deltas.count)
        let expectedMeanDelta = Double(allocation.numberOfBytes) * 0.6 // only 60% to mitigate external allocations in the process

        XCTAssertLessThan(
            meanDelta,
            expectedMeanDelta,
            "Mean delta \(toMB(meanDelta))MB is not less than \(toMB(expectedMeanDelta))MB"
        )
    }

    // MARK: - Helpers

    private func toMB(_ bytes: Double) -> Double {
        return round(bytes / (1_024 * 1_024) * 100) / 100
    }
}
