/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import TestUtilities

// swiftlint:disable duplicate_imports
import DatadogMachProfiler.Cxx
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
/// sampling interval (524288 bytes for a standard heap profile).
final class HeapPprofPackerTests: XCTestCase {

    // MARK: - Heap sample type and period

    func testHeapPack_sampleTypes_areInGoAlignedOrder() throws {
        // Given — a heap profile with sampling interval 524288 (standard heap period)
        let profile = try XCTUnwrap(dd_pprof_create(524288))
        defer { dd_pprof_destroy(profile) }

        // Inject one raw heap sample: alloc_objects=3, alloc_space=4096,
        //                             inuse_objects=2, inuse_space=2048
        // location_id=1 is a synthetic placeholder (no real location needed for this assertion).
        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4096, 2, 2048)

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
        let profile = try XCTUnwrap(dd_pprof_create(524288))
        defer { dd_pprof_destroy(profile) }

        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4096, 2, 2048)

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
        let profile = try XCTUnwrap(dd_pprof_create(524288))
        defer { dd_pprof_destroy(profile) }

        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4096, 2, 2048)

        // When
        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize_heap_for_testing(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Then
        XCTAssertEqual(pprof.pointee.period, 524288, "period must be 524288")
    }

    func testHeapPack_sampleValues_matchInjectedTuple() throws {
        // Given — values in Go-aligned order: {alloc_objects, alloc_space, inuse_objects, inuse_space}
        let profile = try XCTUnwrap(dd_pprof_create(524288))
        defer { dd_pprof_destroy(profile) }

        dd_pprof_add_heap_sample_for_testing(profile, 1, 3, 4096, 2, 2048)

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
        XCTAssertEqual(sample.pointee.value[1], 4096, "value[1] = alloc_space")
        XCTAssertEqual(sample.pointee.value[2], 2,    "value[2] = inuse_objects")
        XCTAssertEqual(sample.pointee.value[3], 2048, "value[3] = inuse_space")
    }

    // MARK: - Wall-time path is untouched

    func testWallTimePack_isUnaffected_byHeapAdditions() throws {
        // Confirms the existing wall-time path still emits exactly 1 sample type.
        let profile = try XCTUnwrap(dd_pprof_create(10_000_000))
        defer { dd_pprof_destroy(profile) }

        let trace = UnsafeMutablePointer<stack_trace_t>.allocate(capacity: 1)
        trace.pointee = .mockWith(tid: 1, addresses: [0x100001000])
        defer { dd_free(trace) }
        dd_pprof_add_samples(profile, trace, 1)

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        defer { dd_pprof_free_serialized_data(data) }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, size, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        XCTAssertEqual(pprof.pointee.n_sample_type, 1,
                       "Wall-time profile must still emit exactly 1 sample type")
        let vt = try XCTUnwrap(pprof.pointee.sample_type[0])
        let typeStr = String(cString: pprof.pointee.string_table[Int(vt.pointee.type)]!)
        XCTAssertEqual(typeStr, "wall-time", "Wall-time sample type must be 'wall-time'")
    }
}
#endif // !os(watchOS)
