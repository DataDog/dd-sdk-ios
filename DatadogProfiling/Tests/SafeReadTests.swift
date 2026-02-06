/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogMachProfiler.Testing

// Warning: To run successfully these tests, the LLDB debugger should be detached in the target schema,
// like when using xcodebuild where the tests run in a "headless" mode without the debugger.
final class SafeReadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        init_safe_read_handlers_for_testing()
    }

    func testValidMemoryRead() {
        // Given
        var validValue: UInt64 = 0x1122334455667788
        var result: UInt64 = 0

        // When
        let success = safe_read_memory_for_testing(&validValue, &result, MemoryLayout<UInt64>.size)

        // Then
        XCTAssertTrue(success)
        XCTAssertEqual(result, 0x1122334455667788)
    }

    func testInvalidMemoryRead() {
        // Given
        let invalidPtr = get_invalid_address()
        var result: UInt64 = 0

        // When
        let success = safe_read_memory_for_testing(invalidPtr, &result, MemoryLayout<UInt64>.size)

        // Then
        XCTAssertFalse(success)
    }

    func testRecoveryAndReuse() {
        // Given
        var result: UInt64 = 0
        let invalidPtr = get_invalid_address()
        var validValue: UInt64 = 42

        // When read INVALID memory
        let failedRead = safe_read_memory_for_testing(invalidPtr, &result, MemoryLayout<UInt64>.size)
        XCTAssertFalse(failedRead, "First invalid read should fail")

        // When immediately try a VALID read
        let success2 = safe_read_memory_for_testing(&validValue, &result, MemoryLayout<UInt64>.size)
        XCTAssertTrue(success2, "Subsequent valid read should succeed")
        XCTAssertEqual(result, 42)

        // When trigger crash again
        let failedRead2 = safe_read_memory_for_testing(invalidPtr, &result, MemoryLayout<UInt64>.size)
        XCTAssertFalse(failedRead2, "Second invalid read should fail safely")
    }

    func testMultithreadedCrashes() {
        // Given
        let iterations = 1_000
        let expectation = self.expectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            var result: UInt64 = 0

            //Even threads
            if i % 2 == 0 {
                //Read VALID memory
                var valid = UInt64(i)
                let success = safe_read_memory_for_testing(&valid, &result, MemoryLayout<UInt64>.size)
                XCTAssertTrue(success, "Thread \(i) valid read failed")
            }
            // Odd threads
            else {
                // Read INVALID memory (Crash)
                let invalidPtr = self.get_invalid_address()
                let success = safe_read_memory_for_testing(invalidPtr, &result, MemoryLayout<UInt64>.size)
                XCTAssertFalse(success, "Thread \(i) invalid read should have failed safely")
            }

            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    private func get_invalid_address() -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(bitPattern: 0xDEADBEEF)!
    }
}
#endif // !os(watchOS)
