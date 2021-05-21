/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

internal class VitalMemoryReaderTest: XCTestCase {
    func testReadMemory() throws {
        let reader = VitalMemoryReader()

        let result = reader.readVitalData()

        XCTAssertNotNil(result)
    }

    func testWhenMemoryConsumptionGrows() {
        // Given
        let reader = VitalMemoryReader()
        let threshold = reader.readVitalData()
        let allocationSize = 128 * 1_024

        // When
        let intPointer = UnsafeMutablePointer<Int>.allocate(capacity: allocationSize)
        for i in 0..<allocationSize {
            (intPointer + i).initialize(to: i)
        }
        let measure = reader.readVitalData()
        intPointer.deallocate()

        // Then
        // Test that at least half the allocated size is accounted for to mitigate flakiness in memory readings
        let expectedAllocatedSize = allocationSize * MemoryLayout<Int>.stride / 2
        XCTAssertNotNil(threshold)
        XCTAssertNotNil(measure)
        let delta = measure! - threshold!
        XCTAssertGreaterThanOrEqual(delta, Double(expectedAllocatedSize))
    }

    func testWhenMemoryConsumptionShrinks() {
        // Given
        let reader = VitalMemoryReader()
        let allocationSize = 128 * 1_024
        let intPointer = UnsafeMutablePointer<Int>.allocate(capacity: allocationSize)
        for i in 0..<allocationSize {
            (intPointer + i).initialize(to: i)
        }
        let threshold = reader.readVitalData()

        // When
        intPointer.deallocate()
        let measure = reader.readVitalData()

        // Then
        // Test that at least half the allocated size is accounted for to mitigate flakiness in memory readings
        let expectedAllocatedSize = allocationSize * MemoryLayout<Int>.stride / 2
        XCTAssertNotNil(threshold)
        XCTAssertNotNil(measure)
        let delta = threshold! - measure!
        XCTAssertGreaterThanOrEqual(delta, Double(expectedAllocatedSize))
    }
}
