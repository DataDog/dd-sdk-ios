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
        timestampNs: UInt64 = 0,
        className: UnsafePointer<CChar>? = nil,
        source: dd_memory_source_t = DD_MEMORY_SOURCE_ZONE
    ) -> dd_memory_sample_t {
        var sample = dd_memory_sample_t()
        sample.addr = 0
        sample.size = size
        sample.weight = weight
        sample.class_name = className
        sample.source = source
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
        let size = dd_memory_snapshot_to_pprof(nil, nil, nil, nil, &out)
        XCTAssertEqual(size, 0)
        XCTAssertNil(out)
    }

    func testEmptySnapshot_returns0() {
        var snapshot = dd_memory_snapshot_t()
        snapshot.samples = nil
        snapshot.sample_count = 0
        snapshot.timestamp_ns = 0
        var out: UnsafeMutablePointer<UInt8>?
        let size = dd_memory_snapshot_to_pprof(&snapshot, nil, nil, nil, &out)
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
            let n = dd_memory_snapshot_to_pprof(&snapshot, nil, nil, nil, &out)
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

    // MARK: - class_name / source labels + aggregation split

    func testSameStackDifferentClassAndSource_doesNotAggregate() throws {
        let sharedIP: UInt64 = 0xBEEF_0000

        let (byteCount, data): (Int, UnsafeMutablePointer<UInt8>?) =
            "NSFoo".withCString { objcName in
            "SwiftBar".withCString { swiftName in
                var samples: [dd_memory_sample_t] = [
                    Self.makeSample(size: 1024, weight: 1.0, addresses: [sharedIP],
                                    className: objcName, source: DD_MEMORY_SOURCE_OBJC),
                    Self.makeSample(size: 1024, weight: 1.0, addresses: [sharedIP],
                                    className: swiftName, source: DD_MEMORY_SOURCE_SWIFT),
                ]
                return samples.withUnsafeMutableBufferPointer { buf in
                    var snapshot = dd_memory_snapshot_t()
                    snapshot.samples = buf.baseAddress
                    snapshot.sample_count = buf.count
                    snapshot.timestamp_ns = 0
                    var out: UnsafeMutablePointer<UInt8>?
                    let n = dd_memory_snapshot_to_pprof(&snapshot, nil, nil, nil, &out)
                    return (n, out)
                }
            }
        }
        defer { if let d = data { free(d) } }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, byteCount, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Same stack, different (class, source) => two distinct samples.
        XCTAssertEqual(pprof.pointee.n_sample, 2)

        let strings = pprof.pointee.string_table!
        var seen: [(className: String, source: String)] = []
        for si in 0..<Int(pprof.pointee.n_sample) {
            guard let s = pprof.pointee.sample?[si] else { continue }
            var byKey: [String: String] = [:]
            for li in 0..<Int(s.pointee.n_label) {
                guard let lbl = s.pointee.label?[li] else { continue }
                let key = String(cString: strings[Int(lbl.pointee.key)]!)
                if lbl.pointee.str != 0 { byKey[key] = String(cString: strings[Int(lbl.pointee.str)]!) }
            }
            seen.append((byKey["class_name"] ?? "", byKey["source"] ?? ""))
        }
        XCTAssertTrue(seen.contains(where: { $0 == ("NSFoo", "objc") }), "objc sample+labels missing")
        XCTAssertTrue(seen.contains(where: { $0 == ("SwiftBar", "swift") }), "swift sample+labels missing")
    }

    // MARK: - independent alloc_* vs inuse_* (two-snapshot encoder)

    func testAllocAndInuseSnapshots_populateIndependently() throws {
        let ipLive: UInt64 = 0xA11_0000
        let ipTransient: UInt64 = 0xB22_0000

        let (byteCount, data): (Int, UnsafeMutablePointer<UInt8>?) =
            "LiveClass".withCString { liveName in
            "TransientClass".withCString { transientName in
                // Live set: only LiveClass.
                var inuseSamples = [
                    Self.makeSample(size: 1000, weight: 1.0, addresses: [ipLive],
                                    className: liveName, source: DD_MEMORY_SOURCE_SWIFT),
                ]
                // Allocation window: LiveClass (still alive) + TransientClass (freed within window).
                var allocSamples = [
                    Self.makeSample(size: 1000, weight: 1.0, addresses: [ipLive],
                                    className: liveName, source: DD_MEMORY_SOURCE_SWIFT),
                    Self.makeSample(size: 2000, weight: 1.0, addresses: [ipTransient],
                                    className: transientName, source: DD_MEMORY_SOURCE_OBJC),
                ]
                return inuseSamples.withUnsafeMutableBufferPointer { inuseBuf in
                    allocSamples.withUnsafeMutableBufferPointer { allocBuf in
                        var inuse = dd_memory_snapshot_t()
                        inuse.samples = inuseBuf.baseAddress
                        inuse.sample_count = inuseBuf.count
                        var alloc = dd_memory_snapshot_t()
                        alloc.samples = allocBuf.baseAddress
                        alloc.sample_count = allocBuf.count
                        var out: UnsafeMutablePointer<UInt8>?
                        let n = dd_memory_snapshots_to_pprof(&inuse, &alloc, nil, nil, nil, &out)
                        return (n, out)
                    }
                }
            }
        }
        defer { if let d = data { free(d) } }

        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, byteCount, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        // Two distinct keys => two samples.
        XCTAssertEqual(pprof.pointee.n_sample, 2)

        let strings = pprof.pointee.string_table!
        // Collect (class_name) -> [alloc_objects, alloc_space, inuse_objects, inuse_space]
        var byClass: [String: [Int64]] = [:]
        for si in 0..<Int(pprof.pointee.n_sample) {
            guard let s = pprof.pointee.sample?[si] else { continue }
            var className = ""
            for li in 0..<Int(s.pointee.n_label) {
                guard let lbl = s.pointee.label?[li] else { continue }
                if String(cString: strings[Int(lbl.pointee.key)]!) == "class_name", lbl.pointee.str != 0 {
                    className = String(cString: strings[Int(lbl.pointee.str)]!)
                }
            }
            var values: [Int64] = []
            for vi in 0..<Int(s.pointee.n_value) { values.append(s.pointee.value[vi]) }
            byClass[className] = values
        }

        // LiveClass: allocated AND live → all four non-zero.
        let live = try XCTUnwrap(byClass["LiveClass"])
        XCTAssertEqual(live, [1, 1000, 1, 1000], "LiveClass: alloc_* and inuse_* both populated")

        // TransientClass: allocated but freed → alloc_* set, inuse_* zero.
        let transient = try XCTUnwrap(byClass["TransientClass"])
        XCTAssertEqual(transient, [1, 2000, 0, 0], "TransientClass: alloc_* only, inuse_* must be zero")
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
            let n = dd_memory_snapshot_to_pprof(&snapshot, nil, nil, nil, &out)
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

    // MARK: - RUM correlation labels

    /// Converter called with all three RUM IDs must attach string labels
    /// `session_id`, `view_id`, and `application_id` to every emitted sample.
    func testRUMLabels_allPresent() throws {
        let sample = Self.makeSample(size: 1024, weight: 1.0, addresses: [0xDEAD_0001])
        var samples = [sample]

        let (byteCount, data) = samples.withUnsafeMutableBufferPointer { buf -> (Int, UnsafeMutablePointer<UInt8>?) in
            var snapshot = dd_memory_snapshot_t()
            snapshot.samples = buf.baseAddress
            snapshot.sample_count = buf.count
            snapshot.timestamp_ns = 0
            var out: UnsafeMutablePointer<UInt8>?
            let n = dd_memory_snapshot_to_pprof(&snapshot, "S", "V", "A", &out)
            return (n, out)
        }
        defer { if let d = data { free(d) } }

        let pprof = try XCTUnwrap(
            perftools__profiles__profile__unpack(nil, byteCount, data),
            "Failed to unpack pprof protobuf"
        )
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        XCTAssertEqual(pprof.pointee.n_sample, 1)
        let pprofSample = try XCTUnwrap(pprof.pointee.sample?[0])
        let strings = pprof.pointee.string_table!

        // Collect all string labels emitted on this sample.
        var labelsByKey: [String: String] = [:]
        for li in 0..<Int(pprofSample.pointee.n_label) {
            guard let lbl = pprofSample.pointee.label?[li] else { continue }
            let key = String(cString: strings[Int(lbl.pointee.key)]!)
            // String label: str field is a non-zero string-table index.
            if lbl.pointee.str != 0 {
                labelsByKey[key] = String(cString: strings[Int(lbl.pointee.str)]!)
            }
        }

        XCTAssertEqual(labelsByKey["session_id"],     "S", "session_id label mismatch")
        XCTAssertEqual(labelsByKey["view_id"],        "V", "view_id label mismatch")
        XCTAssertEqual(labelsByKey["application_id"], "A", "application_id label mismatch")
    }

    // MARK: - No spurious end_timestamp_ns label on heap samples

    /// Heap samples have `timestamp_uptime_ns == 0`, so `for_each_label` must NOT
    /// emit an `end_timestamp_ns` label — that label is wall-time-only.
    func testHeapSamples_noEndTimestampNsLabel() throws {
        let sample = Self.makeSample(size: 1024, weight: 1.0, addresses: [0xDEAD_0003])
        var samples = [sample]

        let (byteCount, data) = samples.withUnsafeMutableBufferPointer { buf -> (Int, UnsafeMutablePointer<UInt8>?) in
            var snapshot = dd_memory_snapshot_t()
            snapshot.samples = buf.baseAddress
            snapshot.sample_count = buf.count
            snapshot.timestamp_ns = 0
            var out: UnsafeMutablePointer<UInt8>?
            let n = dd_memory_snapshot_to_pprof(&snapshot, "S", "V", "A", &out)
            return (n, out)
        }
        defer { if let d = data { free(d) } }

        let pprof = try XCTUnwrap(
            perftools__profiles__profile__unpack(nil, byteCount, data),
            "Failed to unpack pprof protobuf"
        )
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        XCTAssertEqual(pprof.pointee.n_sample, 1)
        let pprofSample = try XCTUnwrap(pprof.pointee.sample?[0])
        let strings = pprof.pointee.string_table!

        // Collect all label keys emitted on this heap sample.
        var labelKeys: [String] = []
        for li in 0..<Int(pprofSample.pointee.n_label) {
            guard let lbl = pprofSample.pointee.label?[li] else { continue }
            labelKeys.append(String(cString: strings[Int(lbl.pointee.key)]!))
        }

        XCTAssertFalse(
            labelKeys.contains("end_timestamp_ns"),
            "Heap samples must NOT carry an end_timestamp_ns label (timestamp_uptime_ns == 0)"
        )

        // RUM labels must still be present (regression guard).
        XCTAssertTrue(labelKeys.contains("session_id"),     "session_id label must be present")
        XCTAssertTrue(labelKeys.contains("view_id"),        "view_id label must be present")
        XCTAssertTrue(labelKeys.contains("application_id"), "application_id label must be present")
    }

    /// Converter called with NULL IDs must NOT emit RUM correlation labels.
    func testRUMLabels_nullIDs_noLabelsEmitted() throws {
        let sample = Self.makeSample(size: 1024, weight: 1.0, addresses: [0xDEAD_0002])
        var samples = [sample]

        let (byteCount, data) = samples.withUnsafeMutableBufferPointer { buf -> (Int, UnsafeMutablePointer<UInt8>?) in
            var snapshot = dd_memory_snapshot_t()
            snapshot.samples = buf.baseAddress
            snapshot.sample_count = buf.count
            snapshot.timestamp_ns = 0
            var out: UnsafeMutablePointer<UInt8>?
            let n = dd_memory_snapshot_to_pprof(&snapshot, nil, nil, nil, &out)
            return (n, out)
        }
        defer { if let d = data { free(d) } }

        let pprof = try XCTUnwrap(
            perftools__profiles__profile__unpack(nil, byteCount, data),
            "Failed to unpack pprof protobuf"
        )
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }

        XCTAssertEqual(pprof.pointee.n_sample, 1)
        let pprofSample = try XCTUnwrap(pprof.pointee.sample?[0])
        let strings = pprof.pointee.string_table!

        var labelKeys: Set<String> = []
        for li in 0..<Int(pprofSample.pointee.n_label) {
            guard let lbl = pprofSample.pointee.label?[li] else { continue }
            let key = String(cString: strings[Int(lbl.pointee.key)]!)
            labelKeys.insert(key)
        }

        XCTAssertFalse(labelKeys.contains("session_id"),     "No session_id label expected when id is nil")
        XCTAssertFalse(labelKeys.contains("view_id"),        "No view_id label expected when id is nil")
        XCTAssertFalse(labelKeys.contains("application_id"), "No application_id label expected when id is nil")
    }
}
#endif // !os(watchOS)
