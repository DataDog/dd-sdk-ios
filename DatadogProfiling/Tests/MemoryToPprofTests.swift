/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest

// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Pprof
// swiftlint:enable duplicate_imports

/// Tests for `dd_memory_snapshot_to_pprof`.
///
/// Builds a synthetic `dd_memory_snapshot_t` with controlled samples, calls the
/// converter, unpacks the resulting heap-pprof, and verifies:
///   - 4 Go-aligned sample types
///   - Correct aggregation of samples that share the same resolved stack
///   - Correct Poisson-unbiased inuse_space / inuse_objects values
///   - alloc_* == inuse_* (single-snapshot approximation)
final class MemoryToPprofTests: XCTestCase {

    // MARK: - Helpers

    /// Construct a `dd_memory_sample_t` with the given instruction pointers in
    /// the frames tuple.  The `frames` field is a C fixed-size array imported
    /// into Swift as a tuple; we write into it via an unsafe mutable raw pointer.
    private static func makeSample(
        size: UInt64,
        weight: Double,
        addresses: [UInt64],
        timestampNs: UInt64 = 0
    ) -> dd_memory_sample_t {
        var sample = dd_memory_sample_t()
        sample.addr = 0
        sample.size = size
        sample.weight = weight
        sample.class_name = nil
        sample.frame_count = UInt32(min(addresses.count, Int(DD_MEMORY_DEFAULT_STACK_DEPTH)))
        sample.timestamp_ns = timestampNs

        // `frames` is a 64-element C array imported as a 64-tuple.
        // Write the IPs via raw pointer arithmetic to avoid enumerating the tuple.
        withUnsafeMutablePointer(to: &sample.frames) { tuplePtr in
            let rawPtr = UnsafeMutableRawPointer(tuplePtr)
                .bindMemory(to: UInt64.self, capacity: Int(DD_MEMORY_DEFAULT_STACK_DEPTH))
            for (i, ip) in addresses.prefix(Int(DD_MEMORY_DEFAULT_STACK_DEPTH)).enumerated() {
                rawPtr[i] = ip
            }
        }

        return sample
    }

    // MARK: - Guard cases

    func testNullSnapshot_returns0() {
        var out: UnsafeMutablePointer<UInt8>?
        let size = dd_memory_snapshot_to_pprof(nil, &out)
        XCTAssertEqual(size, 0)
        XCTAssertNil(out)
    }

    func testEmptySnapshot_returns0() {
        var snapshot = dd_memory_snapshot_t()
        snapshot.samples = nil
        snapshot.sample_count = 0
        snapshot.timestamp_ns = 0
        var out: UnsafeMutablePointer<UInt8>?
        let size = dd_memory_snapshot_to_pprof(&snapshot, &out)
        XCTAssertEqual(size, 0)
        XCTAssertNil(out)
    }

    // MARK: - Aggregation + value correctness

    /// Two samples sharing the same single instruction-pointer frame must
    /// collapse into one pprof sample whose values are the sum of the
    /// Poisson-unbiased contributions from both inputs.
    func testTwoSamplesWithSameStack_aggregateIntoOne() throws {
        // A non-zero fake instruction pointer.  intern_frame will look it up
        // via dladdr and likely produce an unknown/synthetic mapping.  That is
        // acceptable — we assert on values and aggregation, not on symbol names.
        let sharedIP: UInt64 = 0xDEAD_0000

        let size1: UInt64 = 1024
        let weight1: Double = 3.0  // inuse contribution: size=3072, objects=3
        let size2: UInt64 = 2048
        let weight2: Double = 2.0  // inuse contribution: size=4096, objects=2

        var samples: [dd_memory_sample_t] = [
            Self.makeSample(size: size1, weight: weight1, addresses: [sharedIP]),
            Self.makeSample(size: size2, weight: weight2, addresses: [sharedIP]),
        ]

        let (byteCount, data) = samples.withUnsafeMutableBufferPointer { buf -> (Int, UnsafeMutablePointer<UInt8>?) in
            var snapshot = dd_memory_snapshot_t()
            snapshot.samples = buf.baseAddress
            snapshot.sample_count = buf.count
            snapshot.timestamp_ns = 0

            var out: UnsafeMutablePointer<UInt8>?
            let n = dd_memory_snapshot_to_pprof(&snapshot, &out)
            return (n, out)
        }
        defer { if let d = data { free(d) } }

        // Non-empty output
        XCTAssertGreaterThan(byteCount, 0, "Converter should produce non-empty output")
        let pprof = try XCTUnwrap(
            perftools__profiles__profile__unpack(nil, byteCount, data),
            "Failed to unpack pprof protobuf"
        )
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // -- 4 sample types in Go-aligned order --
        XCTAssertEqual(pprof.pointee.n_sample_type, 4, "Heap profile must have exactly 4 sample types")
        let strings = pprof.pointee.string_table!
        let expectedTypes: [(type: String, unit: String)] = [
            ("alloc_objects", "count"),
            ("alloc_space",   "bytes"),
            ("inuse_objects", "count"),
            ("inuse_space",   "bytes"),
        ]
        for (i, expected) in expectedTypes.enumerated() {
            guard i < Int(pprof.pointee.n_sample_type), let vt = pprof.pointee.sample_type[i] else { continue }
            XCTAssertEqual(String(cString: strings[Int(vt.pointee.type)]!), expected.type,
                           "sample_type[\(i)].type")
            XCTAssertEqual(String(cString: strings[Int(vt.pointee.unit)]!), expected.unit,
                           "sample_type[\(i)].unit")
        }

        // -- Exactly 1 aggregated sample (identical stacks collapsed) --
        XCTAssertEqual(pprof.pointee.n_sample, 1,
                       "Two samples with identical stacks must aggregate to 1")

        let sample = try XCTUnwrap(pprof.pointee.sample[0])
        XCTAssertEqual(sample.pointee.n_value, 4, "Heap sample must carry 4 values")

        // Expected Poisson-unbiased totals.
        // llround(1024 * 3.0) = 3072, llround(2048 * 2.0) = 4096 → inuse_space = 7168
        // llround(3.0) = 3, llround(2.0) = 2                     → inuse_objects = 5
        let expectedInuseSpace: Int64   = 7168
        let expectedInuseObjects: Int64 = 5

        // alloc_* == inuse_* (single-snapshot approximation — no delta tracking yet)
        XCTAssertEqual(sample.pointee.value[0], expectedInuseObjects, "value[0] = alloc_objects")
        XCTAssertEqual(sample.pointee.value[1], expectedInuseSpace,   "value[1] = alloc_space")
        XCTAssertEqual(sample.pointee.value[2], expectedInuseObjects, "value[2] = inuse_objects")
        XCTAssertEqual(sample.pointee.value[3], expectedInuseSpace,   "value[3] = inuse_space")
    }

    // MARK: - period_type and period

    func testPeriodType_isSpaceBytes() throws {
        let sample = Self.makeSample(size: 1024, weight: 1.0, addresses: [0xDEAD_0000])
        var samples = [sample]

        let (byteCount, data) = samples.withUnsafeMutableBufferPointer { buf -> (Int, UnsafeMutablePointer<UInt8>?) in
            var snapshot = dd_memory_snapshot_t()
            snapshot.samples = buf.baseAddress
            snapshot.sample_count = buf.count
            snapshot.timestamp_ns = 0
            var out: UnsafeMutablePointer<UInt8>?
            let n = dd_memory_snapshot_to_pprof(&snapshot, &out)
            return (n, out)
        }
        defer { if let d = data { free(d) } }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, byteCount, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        let strings = pprof.pointee.string_table!
        let periodType = try XCTUnwrap(pprof.pointee.period_type)
        XCTAssertEqual(String(cString: strings[Int(periodType.pointee.type)]!), "space")
        XCTAssertEqual(String(cString: strings[Int(periodType.pointee.unit)]!), "bytes")
        XCTAssertEqual(pprof.pointee.period, Int64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES),
                       "period must equal DD_MEMORY_POISSON_DEFAULT_RATE_BYTES (524288)")
    }
}
#endif // !os(watchOS)
