/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest

// swiftlint:disable duplicate_imports
import DatadogMachProfiler.Pprof
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports

/// Tests for the heap pprof packing path (`profile_pprof_pack_heap`).
///
/// The heap packer emits four Go-aligned sample types in this order:
///   [0] alloc_objects / count
///   [1] alloc_space   / bytes
///   [2] inuse_objects / count
///   [3] inuse_space   / bytes
///
/// The period_type is space/bytes and the period equals the profile's
/// sampling interval (524_288 bytes for a standard heap profile).
final class HeapPprofPackerTests: XCTestCase {
    // MARK: - Heap sample type and period

    func testHeapPack_sampleTypes_areInGoAlignedOrder() throws {
        // Given — a heap profile with sampling interval 524_288 (standard heap period)
        let profile = try XCTUnwrap(dd_pprof_create(524_288))
        defer { dd_pprof_destroy(profile) }

        // Inject one raw heap sample: alloc_objects=3, alloc_space=4_096,
        //                             inuse_objects=2, inuse_space=2_048
        // location_id=1 is a synthetic placeholder (no real location needed for this assertion).
        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4_096, 2, 2_048)

        // When
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize_heap_for_testing(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        XCTAssertGreaterThan(size, 0, "Heap packer should produce non-empty output")
        XCTAssertNotNil(data)

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Then — exactly 4 sample types
        XCTAssertEqual(pprof.pointee.n_sample_type, 4, "Heap profile must have exactly 4 sample types")

        let strings = pprof.pointee.string_table!

        let expectedTypes: [(type: String, unit: String)] = [
            ("alloc_objects", "count"),
            ("alloc_space",   "bytes"),
            ("inuse_objects", "count"),
            ("inuse_space",   "bytes"),
        ]

        for (index, expected) in expectedTypes.enumerated() {
            let vt = try XCTUnwrap(pprof.pointee.sample_type[index])
            let typeStr  = String(cString: strings[Int(vt.pointee.type)]!)
            let unitStr  = String(cString: strings[Int(vt.pointee.unit)]!)
            XCTAssertEqual(typeStr, expected.type, "sample_type[\(index)].type mismatch")
            XCTAssertEqual(unitStr, expected.unit, "sample_type[\(index)].unit mismatch")
        }
    }

    func testHeapPack_periodType_isSpaceBytes() throws {
        // Given
        let profile = try XCTUnwrap(dd_pprof_create(524_288))
        defer { dd_pprof_destroy(profile) }

        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4_096, 2, 2_048)

        // When
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize_heap_for_testing(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Then — period_type = space / bytes
        let strings = pprof.pointee.string_table!
        let periodType = try XCTUnwrap(pprof.pointee.period_type)
        let typeStr = String(cString: strings[Int(periodType.pointee.type)]!)
        let unitStr = String(cString: strings[Int(periodType.pointee.unit)]!)
        XCTAssertEqual(typeStr, "space", "period_type.type should be 'space'")
        XCTAssertEqual(unitStr, "bytes", "period_type.unit should be 'bytes'")
    }

    func testHeapPack_period_equals524288() throws {
        // Given
        let profile = try XCTUnwrap(dd_pprof_create(524_288))
        defer { dd_pprof_destroy(profile) }

        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4_096, 2, 2_048)

        // When
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize_heap_for_testing(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Then
        XCTAssertEqual(pprof.pointee.period, 524_288, "period must be 524_288")
    }

    func testHeapPack_sampleValues_matchInjectedTuple() throws {
        // Given — values in Go-aligned order: {alloc_objects, alloc_space, inuse_objects, inuse_space}
        let profile = try XCTUnwrap(dd_pprof_create(524_288))
        defer { dd_pprof_destroy(profile) }

        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4_096, 2, 2_048)

        // When
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize_heap_for_testing(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Then — exactly 1 sample with 4 values in the right order
        XCTAssertEqual(pprof.pointee.n_sample, 1, "Should have exactly one sample")
        let sample = try XCTUnwrap(pprof.pointee.sample[0])
        XCTAssertEqual(sample.pointee.n_value, 4, "Heap sample must carry 4 values")
        XCTAssertEqual(sample.pointee.value[0], 3,    "value[0] = alloc_objects")
        XCTAssertEqual(sample.pointee.value[1], 4_096, "value[1] = alloc_space")
        XCTAssertEqual(sample.pointee.value[2], 2,    "value[2] = inuse_objects")
        XCTAssertEqual(sample.pointee.value[3], 2_048, "value[3] = inuse_space")
    }

    func testHeapPackAllocationFailureReleasesEveryTemporaryBlock() throws {
        let profile = try XCTUnwrap(dd_pprof_create(524_288))
        defer { dd_pprof_destroy(profile) }
        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4_096, 2, 2_048)

        var data: UnsafeMutablePointer<UInt8>?
        var allocationAttempts = 0
        var outstandingAllocations = 0
        let size = dd_pprof_serialize_heap_with_allocation_failure_for_testing(
            profile, .max, &allocationAttempts, &outstandingAllocations, &data
        )
        XCTAssertGreaterThan(size, 0)
        XCTAssertNotNil(data)
        XCTAssertEqual(outstandingAllocations, 0)
        dd_pprof_free_serialized_data(data)
        data = nil
        XCTAssertGreaterThan(allocationAttempts, 1)

        // Exercise initial allocation, partially built arrays and final output allocation.
        for failureIndex in 0..<allocationAttempts {
            var attempts = 0
            var outstanding = 0
            var failedData = UnsafeMutablePointer<UInt8>(bitPattern: 1)
            let failedSize = dd_pprof_serialize_heap_with_allocation_failure_for_testing(
                profile, failureIndex, &attempts, &outstanding, &failedData
            )
            XCTAssertEqual(failedSize, 0, "Failure at allocation \(failureIndex)")
            XCTAssertNil(failedData, "Failed serialization must clear its output")
            XCTAssertEqual(attempts, failureIndex + 1)
            XCTAssertEqual(outstanding, 0, "Temporary blocks leaked after allocation \(failureIndex)")
        }

        // Fault injection is local to each call; the same profile remains serializable.
        let recoveredSize = dd_pprof_serialize_heap_for_testing(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }
        XCTAssertGreaterThan(recoveredSize, 0)
        let unpacked = try XCTUnwrap(perftools__profiles__profile__unpack(nil, recoveredSize, data))
        defer { perftools__profiles__profile__free_unpacked(unpacked, nil) }
        XCTAssertEqual(unpacked.pointee.sample[0]!.pointee.value[1], 4_096)
    }

    func testHeapPackInvalidInputClearsOutput() {
        var data = UnsafeMutablePointer<UInt8>(bitPattern: 1)
        XCTAssertEqual(dd_pprof_serialize_heap_for_testing(nil, &data), 0)
        XCTAssertNil(data)
    }

    // MARK: - Wall-time path is untouched

    func testWallTimePack_isUnaffected_byHeapAdditions() throws {
        // Confirms the existing wall-time path still emits exactly 1 sample type.
        let profile = try XCTUnwrap(dd_pprof_create(10_000_000))
        defer { dd_pprof_destroy(profile) }

        addTrace(to: profile)

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        XCTAssertEqual(
            pprof.pointee.n_sample_type,
            1,
            "Wall-time profile must still emit exactly 1 sample type"
        )
        let vt = try XCTUnwrap(pprof.pointee.sample_type[0])
        let typeStr = String(cString: pprof.pointee.string_table[Int(vt.pointee.type)]!)
        XCTAssertEqual(typeStr, "wall-time", "Wall-time sample type must be 'wall-time'")
    }

    func testCPUTimePackRetainsBothSampleTypesAndValues() throws {
        let profile = try XCTUnwrap(dd_pprof_create_with_cpu_time(10_000_000, true))
        defer { dd_pprof_destroy(profile) }
        addTrace(to: profile)

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }
        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }
        XCTAssertEqual(pprof.pointee.n_sample_type, 2)
        let sampleTypes = (0..<pprof.pointee.n_sample_type).map { index in
            let type = pprof.pointee.sample_type[index]!.pointee.type
            return String(cString: pprof.pointee.string_table[Int(type)]!)
        }
        XCTAssertEqual(sampleTypes, ["wall-time", "cpu-time"])
        let sample = try XCTUnwrap(pprof.pointee.sample[0]).pointee
        XCTAssertEqual(sample.n_value, 2)
        XCTAssertEqual(sample.value[0], 10_000_000)
        XCTAssertEqual(sample.value[1], 4_000_000)
    }

    private func addTrace(to profile: OpaquePointer) {
        var frame = stack_frame_t()
        frame.instruction_ptr = 0x1_0000_1000
        var trace = stack_trace_t()
        trace.tid = 1
        trace.timestamp = 1_000_000_000
        trace.sampling_interval_nanos = 10_000_000
        trace.cpu_time_nanos = 4_000_000
        trace.frame_count = 1
        withUnsafeMutablePointer(to: &frame) { framePointer in
            trace.frames = framePointer
            dd_pprof_add_samples(profile, &trace, 1)
        }
    }
}
#endif // !os(watchOS)
