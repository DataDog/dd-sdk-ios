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

final class MemoryToPprofTests: XCTestCase {
    func testMissingOrEmptyViewProducesNoProfile() {
        var output: UnsafeMutablePointer<UInt8>?
        XCTAssertEqual(dd_memory_aggregates_to_pprof(nil, nil, nil, nil, &output), 0)
        XCTAssertNil(output)

        var view = dd_memory_aggregation_view_t()
        XCTAssertEqual(dd_memory_aggregates_to_pprof(&view, nil, nil, nil, &output), 0)
        XCTAssertNil(output)

        view.count = 1
        XCTAssertEqual(dd_memory_aggregates_to_pprof(&view, nil, nil, nil, &output), 0)
        XCTAssertNil(output)
    }

    func testMissingOutputProducesNoProfile() {
        var aggregate = makeAggregate(allocObjects: 1, allocSpace: 1_024)
        withUnsafePointer(to: &aggregate) { sample in
            var view = dd_memory_aggregation_view_t(samples: sample, count: 1)
            XCTAssertEqual(dd_memory_aggregates_to_pprof(&view, nil, nil, nil, nil), 0)
        }
    }

    func testHeapSampleTypesAndPeriod() throws {
        let profile = try encode([makeAggregate(allocObjects: 2, allocSpace: 2_048)])
        XCTAssertEqual(profile.sampleTypes, [
            "alloc_objects/count", "alloc_space/bytes", "inuse_objects/count", "inuse_space/bytes"
        ])
        XCTAssertEqual(profile.periodType, "space/bytes")
        XCTAssertEqual(profile.period, 512 * 1_024)
    }

    func testFractionalWindowTotalsAreRoundedOnlyAtSerialization() throws {
        let window = try XCTUnwrap(dd_memory_allocation_window_create())
        defer { dd_memory_allocation_window_destroy(window) }
        let generation = dd_memory_allocation_window_start(window)
        defer { dd_memory_allocation_window_stop(window) }
        for (index, size) in [UInt64(3), 7, 11].enumerated() {
            var sample = dd_memory_live_sample_t()
            sample.address = UnsafeRawPointer(bitPattern: 0x1_0000 + index * 16)
            sample.size = size
            sample.weight = 0.4
            sample.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
            sample.frame_count = 1
            sample.frames.0 = 0xDEAD_0000
            XCTAssertEqual(
                dd_memory_allocation_window_record(window, generation, &sample),
                DD_MEMORY_LIVE_SET_INSERTED
            )
            if index < 2 {
                XCTAssertTrue(dd_memory_allocation_window_remove(window, generation, sample.address))
            }
        }
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        var view = dd_memory_allocation_window_view(window)
        let profile = try encode(view: &view)
        XCTAssertEqual(profile.samples.count, 1)
        // Fractional totals are [1.2, 8.4, 0.4, 4.4], despite two objects being freed.
        XCTAssertEqual(profile.samples[0].values, [1, 8, 0, 4])
    }

    func testAllocationAndLiveTotalsRemainIndependent() throws {
        let profile = try encode([
            makeAggregate(allocObjects: 1, allocSpace: 1_000, inuseObjects: 1, inuseSpace: 1_000),
            makeAggregate(allocObjects: 2, allocSpace: 2_000),
            makeAggregate(inuseObjects: 3, inuseSpace: 3_000)
        ])
        XCTAssertEqual(profile.samples.map(\.values), [
            [1, 1_000, 1, 1_000], [2, 2_000, 0, 0], [0, 0, 3, 3_000]
        ])
    }

    func testStackClassAndSourceLabelsSurviveEncoding() throws {
        let profile = try "NSObjectType".withCString { objcName in
            try "SwiftBoxTrailingBytes".withCString { swiftName in
                var resolvedName = dd_swift_class_name_t(data: swiftName, length: 8)
                return try withUnsafePointer(to: &resolvedName) { namePointer in
                    var objc = makeAggregate(allocObjects: 1, allocSpace: 1_024)
                    objc.key.class_name = objcName
                    var swift = makeAggregate(allocObjects: 1, allocSpace: 1_024)
                    swift.key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
                    swift.key.swift_metadata = OpaquePointer(namePointer)
                    swift.key.swift_name_resolver = resolveMemoryPprofSwiftName
                    return try encode([objc, swift])
                }
            }
        }
        XCTAssertEqual(profile.samples.count, 2)
        XCTAssertEqual(profile.samples[0].labels["allocation class"], "NSObjectType")
        XCTAssertEqual(profile.samples[0].labels["source"], "objc")
        XCTAssertEqual(profile.samples[1].labels["allocation class"], "SwiftBox")
        XCTAssertEqual(profile.samples[1].labels["source"], "swift")
        XCTAssertEqual(profile.samples.map(\.addresses), [[0xDEAD_0000], [0xDEAD_0000]])
    }

    func testMissingClassNamesAreOmitted() throws {
        var aggregate = makeAggregate(allocObjects: 1, allocSpace: 1_024)
        aggregate.key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
        let profile = try encode([aggregate])
        XCTAssertNil(profile.samples[0].labels["allocation class"])
        XCTAssertEqual(profile.samples[0].labels["source"], "swift")
    }

    func testCorrelationLabelsAreAttachedWithoutWallTimeLabels() throws {
        let profile = try encode(
            [makeAggregate(allocObjects: 1, allocSpace: 1_024)],
            sessionID: "session",
            viewID: "view",
            applicationID: "application"
        )
        let labels = try XCTUnwrap(profile.samples.first?.labels)
        XCTAssertEqual(labels["session_id"], "session")
        XCTAssertEqual(labels["view_id"], "view")
        XCTAssertEqual(labels["application_id"], "application")
        XCTAssertNil(labels["end_timestamp_ns"])
    }

    func testEmptyCorrelationIDsAreOmitted() throws {
        let profile = try encode([makeAggregate(allocObjects: 1, allocSpace: 1_024)])
        let labels = try XCTUnwrap(profile.samples.first?.labels)
        XCTAssertNil(labels["session_id"])
        XCTAssertNil(labels["view_id"])
        XCTAssertNil(labels["application_id"])
    }

    func testTotalsOutsideIntegerRangeAreClamped() throws {
        let aggregate = makeAggregate(
            allocObjects: .infinity,
            allocSpace: Double(Int64.max),
            inuseObjects: .nan,
            inuseSpace: -1
        )
        let profile = try encode([aggregate])
        XCTAssertEqual(profile.samples[0].values, [Int64.max, Int64.max, 0, 0])
    }

    private func makeAggregate(
        allocObjects: Double = 0,
        allocSpace: Double = 0,
        inuseObjects: Double = 0,
        inuseSpace: Double = 0
    ) -> dd_memory_aggregate_t {
        var aggregate = dd_memory_aggregate_t()
        aggregate.key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
        aggregate.key.frame_count = 1
        aggregate.key.frames.0 = 0xDEAD_0000
        aggregate.alloc_objects = allocObjects
        aggregate.alloc_space = allocSpace
        aggregate.inuse_objects = inuseObjects
        aggregate.inuse_space = inuseSpace
        return aggregate
    }

    private struct HeapSample {
        let values: [Int64]
        let labels: [String: String]
        let addresses: [UInt64]
    }

    private struct HeapProfile {
        let sampleTypes: [String]
        let periodType: String
        let period: Int64
        let samples: [HeapSample]
    }

    private func encode(
        _ aggregates: [dd_memory_aggregate_t],
        sessionID: String = "",
        viewID: String = "",
        applicationID: String = ""
    ) throws -> HeapProfile {
        try aggregates.withUnsafeBufferPointer { buffer in
            var view = dd_memory_aggregation_view_t(samples: buffer.baseAddress, count: buffer.count)
            return try encode(view: &view, sessionID: sessionID, viewID: viewID, applicationID: applicationID)
        }
    }

    private func encode(
        view: inout dd_memory_aggregation_view_t,
        sessionID: String = "",
        viewID: String = "",
        applicationID: String = ""
    ) throws -> HeapProfile {
        var data: UnsafeMutablePointer<UInt8>?
        let byteCount = dd_memory_aggregates_to_pprof(&view, sessionID, viewID, applicationID, &data)
        defer { free(data) }
        let pprof = try XCTUnwrap(perftools__profiles__profile__unpack(nil, byteCount, data))
        defer { perftools__profiles__profile__free_unpacked(pprof, nil) }
        let strings = try XCTUnwrap(pprof.pointee.string_table)
        func string(_ index: Int64) -> String {
            String(cString: strings[Int(index)]!)
        }
        let sampleTypes = (0..<pprof.pointee.n_sample_type).map { index in
            let type = pprof.pointee.sample_type[index]!.pointee
            return "\(string(type.type))/\(string(type.unit))"
        }
        var locations: [UInt64: UInt64] = [:]
        for index in 0..<pprof.pointee.n_location {
            let location = pprof.pointee.location[index]!.pointee
            locations[location.id] = location.address
        }
        let samples = (0..<pprof.pointee.n_sample).map { index in
            let sample = pprof.pointee.sample[index]!.pointee
            let values = Array(UnsafeBufferPointer(start: sample.value, count: sample.n_value))
            var labels: [String: String] = [:]
            for labelIndex in 0..<sample.n_label {
                let label = sample.label[labelIndex]!.pointee
                if label.str != 0 {
                    labels[string(label.key)] = string(label.str)
                }
            }
            let addresses = (0..<sample.n_location_id).compactMap { locations[sample.location_id[$0]] }
            return HeapSample(values: values, labels: labels, addresses: addresses)
        }
        let periodType = try XCTUnwrap(pprof.pointee.period_type).pointee
        return HeapProfile(
            sampleTypes: sampleTypes,
            periodType: "\(string(periodType.type))/\(string(periodType.unit))",
            period: pprof.pointee.period,
            samples: samples
        )
    }
}

private func resolveMemoryPprofSwiftName(_ metadata: OpaquePointer?) -> dd_swift_class_name_t {
    guard let metadata else {
        return dd_swift_class_name_t()
    }
    return UnsafeRawPointer(metadata).assumingMemoryBound(to: dd_swift_class_name_t.self).pointee
}

#endif // !os(watchOS)
