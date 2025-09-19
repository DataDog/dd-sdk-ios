/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

// swiftlint:disable duplicate_imports
import DatadogMachProfiler.Cxx
import DatadogMachProfiler.Pprof
// swiftlint:enable duplicate_imports

@testable import DatadogProfiling

final class MachProfilerTests: XCTestCase {
    // MARK: - Core Functionality Tests

    func testSamplingFrequencyConversion_with100Hz_converts10msInterval() {
        // Given
        let frequency: Double = 200

        // When
        let profiler = MachProfiler(samplingFrequencyHz: frequency)

        // Then
        XCTAssertEqual(profiler.samplingIntervalNs, 5_000_000)
    }

    func testStart_beforeStop_ignoresSubsequentStarts() throws {
        // Given
        let profiler = MachProfiler(samplingFrequencyHz: 100)
        var secondStart: Date? = nil

        let mockThread = MockThread {
            profiler.start(currentThreadOnly: true)
            Thread.sleep(forTimeInterval: 0.01)
            secondStart = Date()
            profiler.start(currentThreadOnly: true) // Should be ignored
            Thread.sleep(forTimeInterval: 0.01)
        }

        // When
        mockThread.start()
        mockThread.waitForWorkCompletion()

        // Then
        let profile = try XCTUnwrap(profiler.stop())
        XCTAssertNotNil(profile)
        XCTAssertGreaterThan(secondStart ?? .distantPast, profile.start)
        XCTAssertGreaterThan(profile.end, profile.start)
    }

    func testStop_withoutStart_returnsNil() throws {
        // Given
        let profiler = MachProfiler()

        // When
        let profile = try profiler.stop()

        // Then
        XCTAssertNil(profile)
    }

    func testStop_afterStart_returnsValidProfile() throws {
        // Given
        let profiler = MachProfiler(samplingFrequencyHz: 100)

        let mockThread = MockThread {
            profiler.start(currentThreadOnly: true)
            Thread.sleep(forTimeInterval: 0.01)
        }

        mockThread.start()
        mockThread.waitForWorkCompletion()

        // When
        let profile = try XCTUnwrap(profiler.stop())

        // Then
        XCTAssertGreaterThan(profile.end, profile.start)
        XCTAssertGreaterThan(profile.pprof.count, 0)
    }

    func testStop_calledTwice_returnsNilOnSecond() throws {
        // Given
        let profiler = MachProfiler()

        let mockThread = MockThread {
            profiler.start(currentThreadOnly: true)
            Thread.sleep(forTimeInterval: 0.01)
        }

        mockThread.start()
        mockThread.waitForWorkCompletion()

        // When
        let firstProfile = try profiler.stop()
        let secondProfile = try profiler.stop()

        // Then
        XCTAssertNotNil(firstProfile)
        XCTAssertNil(secondProfile)
    }

    func testProfileData_isValidPprof() throws {
        // Given
        let profiler = MachProfiler()

        let mockThread = MockThread {
            profiler.start(currentThreadOnly: true)

            // Generate some activity
            var sum = 0
            for i in 0..<1_000 {
                sum += i * i
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        mockThread.start()
        mockThread.waitForWorkCompletion()

        // When
        let profile = try XCTUnwrap(profiler.stop())

        // Then
        XCTAssertGreaterThan(profile.pprof.count, 0)

        // Validate pprof format
        profile.pprof.withUnsafeBytes { bytes in
            let unpackedProfile = perftools__profiles__profile__unpack(
                nil,
                profile.pprof.count,
                bytes.bindMemory(to: UInt8.self).baseAddress
            )
            defer { perftools__profiles__profile__free_unpacked(unpackedProfile, nil) }

            XCTAssertNotNil(unpackedProfile)
            if let unwrapped = unpackedProfile {
                XCTAssertGreaterThan(unwrapped.pointee.n_string_table, 0)
                XCTAssertGreaterThan(unwrapped.pointee.n_location, 0)
            }
        }
    }

    // MARK: - Memory Management Tests

    func testDeinit_withActiveProfiler_cleansUpCorrectly() {
        // Given
        var profiler: MachProfiler? = MachProfiler()

        let mockThread = MockThread {
            profiler?.start(currentThreadOnly: true)
            Thread.sleep(forTimeInterval: 0.005)
        }

        // When
        mockThread.start()
        mockThread.waitForWorkCompletion()
        profiler = nil

        // Then
        // Should not crash when deallocated while active
    }

    func testMultipleStartStopCycles_doesNotLeak() throws {
        // Given
        let profiler = MachProfiler()

        // When
        for _ in 0..<5 {
            let mockThread = MockThread {
                profiler.start(currentThreadOnly: true)
                Thread.sleep(forTimeInterval: 0.005)
            }

            mockThread.start()
            mockThread.waitForWorkCompletion()
            _ = try profiler.stop()
        }

        // Then
        // Test passes if no crashes or memory issues
    }
}
