/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

/// Maps `numberOfBytes` of fresh memory and writes to every page, so each allocation grows the process footprint
/// and each deallocation shrinks it. `malloc` would keep and reuse the freed block instead.
private class Allocation {
    fileprivate let numberOfBytes: Int
    private var pointer: UnsafeMutableRawPointer?

    init(numberOfBytes: Int) {
        self.numberOfBytes = numberOfBytes
    }

    func allocate() {
        let pointer = mmap(nil, numberOfBytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        precondition(pointer != MAP_FAILED)
        memset(pointer, 1, numberOfBytes)
        self.pointer = pointer
    }

    func deallocate() {
        munmap(pointer, numberOfBytes)
        pointer = nil
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
