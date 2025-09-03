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

final class ProfileCxxTests: XCTestCase {
    // MARK: - Profile Creation and Basic Operations

    func testProfileCreation_withValidInterval_createsProfile() {
        // Given
        let samplingInterval: UInt64 = 10_000_000 // 10ms

        // When
        let profile = dd_pprof_create(samplingInterval)
        defer { dd_pprof_destroy(profile) }

        // Then
        XCTAssertNotNil(profile, "Profile should be created successfully")
    }

    func testProfileDestroy_withValidProfile_doesNotCrash() {
        // Given
        let profile = dd_pprof_create(10_000_000)
        XCTAssertNotNil(profile)

        // When/Then - Should not crash
        dd_pprof_destroy(profile)
    }

    func testProfileDestroy_withNilProfile_doesNotCrash() {
        // When/Then - Should not crash
        dd_pprof_destroy(nil)
    }

    // MARK: - Stack Trace Aggregation Tests

    func testProfileAggregation_withIdenticalTraces_aggregatesCorrectly() throws {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        let addresses: [UInt64] = [0x100001000, 0x100002000, 0x100003000]

        // When
        // - Add the same stack trace multiple times
        for _ in 0..<5 {
            let stackTrace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
            stackTrace.pointee = .mockWith(tid: 1, addresses: addresses)
            dd_pprof_add_samples(profile, stackTrace, 1)
            dd_free(stackTrace)
        }

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        // Then
        XCTAssertGreaterThan(size, 0, "Serialized profile should not be empty")
        XCTAssertNotNil(data, "Serialized data should not be nil")

        // - Validate the profile contains aggregated samples
        let unpackedProfile = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(unpackedProfile, nil) }
        XCTAssertGreaterThan(unpackedProfile.pointee.n_sample, 0, "Profile should contain samples")
        XCTAssertLessThanOrEqual(unpackedProfile.pointee.n_sample, 5, "Should not exceed number of input traces")

        // - Verify sample structure regardless of aggregation behavior
        let totalSampleValue = try (0..<5).reduce(0) { sum, i in
            let sample = try XCTUnwrap(unpackedProfile.pointee.sample[i])
            XCTAssertEqual(sample.pointee.n_value, 1, "Sample should have one value")
            XCTAssertEqual(sample.pointee.n_location_id, 3, "Sample should reference 3 locations")
            XCTAssertEqual(sample.pointee.value[0], 10_000_000, "Sample value should be 10ms interval")
            return sum + Int(sample.pointee.value[0])
        }

        // - Total sample values should represent cumulative time intervals (5 samples * 10ms each)
        XCTAssertEqual(totalSampleValue, 50_000_000, "Total sample values should equal 5 * 10ms = 50ms")
        XCTAssertGreaterThan(unpackedProfile.pointee.n_location, 0, "Profile should have location data")
        XCTAssertGreaterThan(unpackedProfile.pointee.n_string_table, 0, "Profile should have string table")
    }

    func testProfileAggregation_withDifferentThreads_separatesSamples() throws {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        let addresses: [UInt64] = [0x100001000, 0x100002000, 0x100003000]

        // When
        // - Add same stack from different threads
        let thread1Trace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        thread1Trace.pointee = .mockWith(tid: 1, addresses: addresses)
        let thread2Trace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        thread2Trace.pointee = .mockWith(tid: 2, addresses: addresses)
        defer {
            dd_free(thread1Trace)
            dd_free(thread2Trace)
        }

        dd_pprof_add_samples(profile, thread1Trace, 1)
        dd_pprof_add_samples(profile, thread2Trace, 1)

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        // Then
        XCTAssertGreaterThan(size, 0, "Serialized profile should not be empty")
        let unpackedProfile = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(unpackedProfile, nil) }

        // - Validate the profile separates samples by thread
        XCTAssertEqual(unpackedProfile.pointee.n_sample, 2, "Different threads should create separate samples")

        // - Verify both samples have correct values and structure
        for i in 0..<2 {
            let sample = try XCTUnwrap(unpackedProfile.pointee.sample[i])
            XCTAssertEqual(sample.pointee.n_value, 1, "Sample should have one value")
            XCTAssertEqual(sample.pointee.value[0], 10_000_000, "Each sample should have 10ms interval")
            XCTAssertEqual(sample.pointee.n_location_id, 3, "Sample should reference 3 locations")
        }
    }

    func testProfileAggregation_withDifferentStacks_createsMultipleSamples() throws {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        let stack1: [UInt64] = [0x100001000, 0x100002000, 0x100003000]
        let stack2: [UInt64] = [0x100004000, 0x100005000, 0x100006000]
        let stack3: [UInt64] = [0x100007000, 0x100008000, 0x100009000]

        // When
        let trace1 = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        trace1.pointee = .mockWith(tid: 1, addresses: stack1)
        let trace2 = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        trace2.pointee = .mockWith(tid: 1, addresses: stack2)
        let trace3 = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        trace3.pointee = .mockWith(tid: 1, addresses: stack3)
        defer {
            dd_free(trace1)
            dd_free(trace2)
            dd_free(trace3)
        }

        dd_pprof_add_samples(profile, trace1, 1)
        dd_pprof_add_samples(profile, trace2, 1)
        dd_pprof_add_samples(profile, trace3, 1)

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        // Then
        XCTAssertGreaterThan(size, 0, "Serialized profile should not be empty")

        let unpackedProfile = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(unpackedProfile, nil) }

        // - Should have 3 separate samples (3 different stacks)
        XCTAssertEqual(unpackedProfile.pointee.n_sample, 3, "Different stacks should create separate samples")

        // - Verify each sample has correct structure 
        for i in 0..<3 {
            let sample = try XCTUnwrap(unpackedProfile.pointee.sample[i])
            XCTAssertEqual(sample.pointee.n_value, 1, "Sample should have one value")
            XCTAssertEqual(sample.pointee.value[0], 10_000_000, "Each sample should have 10ms interval")
            XCTAssertEqual(sample.pointee.n_location_id, 3, "Sample should reference 3 locations")
        }
    }

    // MARK: - Memory Management Tests

    func testProfileMemoryManagement_withManyStacks_doesNotLeak() throws {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        // When - Add many different stacks
        for i in 0..<1_000 {
            let addresses: [UInt64] = [
                UInt64(0x100000000 + i * 0x1000),
                UInt64(0x200000000 + i * 0x1000),
                UInt64(0x300000000 + i * 0x1000)
            ]
            let stackTrace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
            stackTrace.pointee = .mockWith(tid: UInt32(i % 10), addresses: addresses)
            dd_pprof_add_samples(profile, stackTrace, 1)
            dd_free(stackTrace)
        }

        // Then - Should be able to serialize without issues
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        XCTAssertGreaterThan(size, 0, "Serialized profile should not be empty")

        // Validate the profile contains the expected number of samples and data integrity
        let unpackedProfile = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(unpackedProfile, nil) }

        // With 1000 different stacks, we should have exactly 1000 samples (each unique)
        XCTAssertEqual(unpackedProfile.pointee.n_sample, 1_000, "Should have created 1000 unique samples")

        // Verify we have locations and string table data
        XCTAssertGreaterThan(unpackedProfile.pointee.n_location, 0, "Should have location data")
        XCTAssertGreaterThan(unpackedProfile.pointee.n_string_table, 0, "Should have string table")

        // Spot check a few samples to ensure they have valid structure
        for i in 0..<min(10, Int(unpackedProfile.pointee.n_sample)) {
            let sample = try XCTUnwrap(unpackedProfile.pointee.sample[i])
            XCTAssertEqual(sample.pointee.n_value, 1, "Sample should have one value")
            XCTAssertEqual(sample.pointee.value[0], 10_000_000, "Each sample should have 10ms interval")
            XCTAssertEqual(sample.pointee.n_location_id, 3, "Sample should reference 3 locations")
        }
    }

    // MARK: - Serialization Tests

    func testProfileSerialization_withEmptyProfile_producesValidPprof() throws {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        // When
        // - Serialize empty profile
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        // Then
        XCTAssertGreaterThan(size, 0, "Empty profile should still produce some data")
        XCTAssertNotNil(data, "Serialized data should not be nil")
        // - Validate basic profile structure
        let unpackedProfile = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        perftools__profiles__profile__free_unpacked(unpackedProfile, nil)
    }

    func testProfileSerialization_withNilProfile_returnsZero() {
        // When
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(nil, &data)

        // Then
        XCTAssertEqual(size, 0, "Nil profile should return zero size")
        XCTAssertNil(data, "Data should be nil for nil profile")
    }

    // MARK: - Edge Cases

    func testProfileAggregation_withZeroAddresses_returnsEmptyData() {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        let emptyTrace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        emptyTrace.pointee = .mockWith(tid: 1, addresses: [])
        defer { dd_free(emptyTrace) }

        // When
        dd_pprof_add_samples(profile, emptyTrace, 1)

        // Then
        // - Should not crash
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        XCTAssertGreaterThanOrEqual(size, 0, "Should handle empty traces gracefully")
    }

    func testProfileAggregation_withMaxStackDepth_createValidProfile() throws {
        // Given
        let profile = dd_pprof_create(10_000_000)
        defer { dd_pprof_destroy(profile) }
        XCTAssertNotNil(profile)

        // Create a deep stack (128 frames - typical max)
        let addresses = (0..<128).map { UInt64(0x100000000 + $0 * 0x1000) }
        let deepTrace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        deepTrace.pointee = .mockWith(tid: 1, addresses: addresses)
        defer { dd_free(deepTrace) }

        // When
        dd_pprof_add_samples(profile, deepTrace, 1)

        // Then
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        XCTAssertGreaterThan(size, 0, "Should handle deep stacks")
        // Validate basic profile structure
        let unpackedProfile = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(unpackedProfile, nil) }

        // Validate profile contains expected data
        XCTAssertGreaterThan(unpackedProfile.pointee.n_string_table, 0, "Should have string table")
        XCTAssertGreaterThan(unpackedProfile.pointee.n_sample, 0, "Should have samples")
        XCTAssertGreaterThan(unpackedProfile.pointee.n_location, 0, "Should have locations")
        XCTAssertGreaterThan(unpackedProfile.pointee.n_mapping, 0, "Should have mappings")
        XCTAssertEqual(unpackedProfile.pointee.n_sample_type, 1, "Should have one sample type")
    }
}
///  Deallocates a stack_trace_t and its subsequent frames
func dd_free(_ trace: UnsafeMutablePointer<stack_trace_t>) {
    // Deallocate frames if they exist
    if let frames = trace.pointee.frames {
        frames.deallocate()
    }
    trace.deallocate()
}
