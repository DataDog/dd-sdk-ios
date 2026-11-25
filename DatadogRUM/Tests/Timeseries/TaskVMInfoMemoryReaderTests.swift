/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

/// Maps `numberOfBytes` of fresh memory and writes to every page, so each allocation grows the process footprint.
/// `malloc` would keep and reuse the freed block instead.
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

class TaskVMInfoMemoryReaderTests: XCTestCase {
    private let allocation = Allocation(
        numberOfBytes: 8 * 1_024 * 1_024 // 8MB is significantly more than any other allocation in tests process
    )

    func testItReadsFootprintAndNonResidentMemory() throws {
        let memory = try XCTUnwrap(TaskVMInfoMemoryReader().readMemory())

        XCTAssertGreaterThan(memory.footprint, 0)
        XCTAssertGreaterThanOrEqual(memory.nonResident, 0)
        XCTAssertLessThanOrEqual(memory.nonResident, memory.footprint)
    }

    func testWhenMemoryConsumptionGrows_itReportsHigherFootprint() throws {
        // Given
        let reader = TaskVMInfoMemoryReader()

        // When
        var deltas: [Double] = []

        try (0..<20).forEach { _ in // measure mean value to mitigate flakiness
            let before = try XCTUnwrap(reader.readMemory()).footprint
            allocation.allocate()
            let after = try XCTUnwrap(reader.readMemory()).footprint
            allocation.deallocate()
            deltas.append(after - before)
        }

        // Then
        let meanDelta = deltas.reduce(0.0, +) / Double(deltas.count)
        let expectedMeanDelta = Double(allocation.numberOfBytes) * 0.6 // only 60% to mitigate external deallocations in the process

        XCTAssertGreaterThan(meanDelta, expectedMeanDelta)
    }
}
