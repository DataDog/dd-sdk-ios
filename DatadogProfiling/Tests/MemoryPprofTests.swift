/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Darwin
import XCTest

// swiftlint:disable duplicate_imports
import DatadogMachProfiler.Pprof
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports

final class MemoryPprofTests: XCTestCase {
    private var encoder: OpaquePointer?
    private var window: OpaquePointer?
    private var generation: UInt64 = 0

    override func setUp() {
        super.setUp()
        encoder = dd_memory_pprof_encoder_create(Int(DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES))
        window = dd_memory_allocation_window_create()
        XCTAssertNotNil(encoder)
        XCTAssertNotNil(window)
        generation = dd_memory_allocation_window_start(window)
    }

    override func tearDown() {
        dd_memory_pprof_encoder_destroy(encoder)
        dd_memory_allocation_window_destroy(window)
        encoder = nil
        window = nil
        super.tearDown()
    }

    func testRoundTripSchemaAndIndependentFractionalTotals() throws {
        try record(address: 0x10000, size: 3, weight: 1.25, className: "Transient", frames: [0x1000, 0x2000])
        XCTAssertTrue(dd_memory_allocation_window_remove(window, generation, UnsafeRawPointer(bitPattern: 0x10000)))
        try record(address: 0x10000, size: 3, weight: 1.25, className: "Transient", frames: [0x1000, 0x2000])
        XCTAssertTrue(dd_memory_allocation_window_remove(window, generation, UnsafeRawPointer(bitPattern: 0x10000)))
        try record(address: 0x20000, size: 10, weight: 2.25, className: "Retained", frames: [0x3000])
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))

        let decoded = try encodeClosedWindow()
        XCTAssertEqual(decoded.types.map { $0.0 }, ["alloc_objects", "alloc_space", "inuse_objects", "inuse_space"])
        XCTAssertEqual(decoded.types.map { $0.1 }, ["count", "bytes", "count", "bytes"])
        XCTAssertEqual(decoded.periodType, "space")
        XCTAssertEqual(decoded.periodUnit, "bytes")
        XCTAssertEqual(decoded.period, 524_288)
        XCTAssertEqual(decoded.defaultType, "inuse_space")
        XCTAssertEqual(decoded.time, 123_000)
        XCTAssertEqual(decoded.duration, 60_000)
        XCTAssertEqual(decoded.samples.count, 2)
        let transient = try XCTUnwrap(decoded.samples.first { $0.labels["allocation class"] == "Transient" })
        XCTAssertEqual(transient.values, [3, 8, 0, 0])
        XCTAssertEqual(transient.frames, [0x1000, 0x2000])
        let retained = try XCTUnwrap(decoded.samples.first { $0.labels["allocation class"] == "Retained" })
        XCTAssertEqual(retained.values, [2, 23, 2, 23])
        XCTAssertEqual(retained.frames, [0x3000])
        for sample in decoded.samples {
            XCTAssertEqual(sample.labels["source"], "objc")
            XCTAssertEqual(Set(sample.labels.keys), ["allocation class", "source"])
        }

        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        let next = try encodeClosedWindow()
        XCTAssertEqual(next.samples.count, 1)
        XCTAssertEqual(next.samples.first?.values, [0, 0, 2, 23])
        XCTAssertEqual(next.samples.first?.labels["allocation class"], "Retained")
    }

    func testClassStackAndSourceStaySeparateInTheWireProfile() throws {
        try record(address: 0x10000, size: 1, weight: 1, className: "First", frames: [0x1000])
        try record(address: 0x20000, size: 2, weight: 1, className: "Second", frames: [0x1000])
        try record(address: 0x30000, size: 3, weight: 1, className: "First", frames: [0x2000])
        try record(
            address: 0x40000,
            size: 4,
            weight: 1,
            className: "First",
            frames: [0x1000],
            source: DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
        )
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        let decoded = try encodeClosedWindow()
        XCTAssertEqual(decoded.samples.count, 4)
        XCTAssertEqual(decoded.samples.filter { $0.labels["source"] == "swift" }.count, 1)
        XCTAssertEqual(decoded.samples.filter { $0.labels["allocation class"] == "First" }.count, 3)
        XCTAssertEqual(decoded.samples.filter { $0.frames == [0x1000] }.count, 3)
    }

    func testClassNameIndexComparesBytesAndFallsBackWhenItsProbeLimitIsReached() throws {
        // These distinct, equal-length names all hash to bucket zero of the
        // 16,384-entry class-name index. The 65th name exceeds its 64-probe bound.
        let collidingNames = [
            "Class0014159", "Class0088025", "Class0119260", "Class0142641", "Class0148986",
            "Class0158510", "Class0178944", "Class0181678", "Class0196631", "Class0205072",
            "Class0233225", "Class0248419", "Class0260468", "Class0288994", "Class0306709",
            "Class0307686", "Class0336950", "Class0348058", "Class0359545", "Class0361898",
            "Class0375847", "Class0386007", "Class0399650", "Class0434514", "Class0454163",
            "Class0458676", "Class0502362", "Class0540690", "Class0559068", "Class0568336",
            "Class0581915", "Class0606276", "Class0634892", "Class0649494", "Class0670819",
            "Class0675806", "Class0684738", "Class0728001", "Class0776697", "Class0815606",
            "Class0855568", "Class0860948", "Class0875549", "Class0890342", "Class0920921",
            "Class0924793", "Class0954952", "Class0965066", "Class0967790", "Class0972140",
            "Class0990856", "Class0994514", "Class1033158", "Class1041893", "Class1082695",
            "Class1083069", "Class1108013", "Class1119976", "Class1143241", "Class1145519",
            "Class1154551", "Class1159875", "Class1166283", "Class1174966", "Class1204063",
        ]
        let names = collidingNames + [collidingNames[0], collidingNames[64]]
        let buffers = names.map { strdup($0)! }
        defer { buffers.forEach { free($0) } }
        XCTAssertNotEqual(buffers[0], buffers[65])
        var aggregates = [dd_memory_aggregate_t](repeating: dd_memory_aggregate_t(), count: names.count)
        for index in aggregates.indices {
            aggregates[index].alloc_objects = 1
            aggregates[index].key.class_name = UnsafePointer(buffers[index])
            aggregates[index].key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
            aggregates[index].key.frame_count = 1
            aggregates[index].key.frames.0 = UInt64(index + 1)
        }
        aggregates.withUnsafeBufferPointer { samples in
            var view = dd_memory_aggregation_view_t(samples: samples.baseAddress, count: samples.count)
            XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
        }

        let decoded = try decode()
        XCTAssertEqual(decoded.samples.map { $0.labels["allocation class"] }, names)
        XCTAssertEqual(decoded.samples.map { $0.frames }, names.indices.map { [UInt64($0 + 1)] })
        XCTAssertEqual(decoded.strings.filter { $0 == collidingNames[0] }.count, 1)
        XCTAssertEqual(decoded.strings.filter { $0 == collidingNames[64] }.count, 2)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).limit_failures, 0)
    }

    func testSwiftNamesAreConsumedBeforeTheResolverReusesItsBuffer() throws {
        var bytes: [CChar] = [0]
        bytes.withUnsafeMutableBufferPointer { buffer in
            var context = HeapPprofReusableNameContext(data: buffer.baseAddress!)
            withUnsafeMutablePointer(to: &context) { metadata in
                var aggregates = [dd_memory_aggregate_t](repeating: dd_memory_aggregate_t(), count: 3)
                for index in aggregates.indices {
                    aggregates[index].alloc_objects = 1
                    aggregates[index].key.swift_metadata = OpaquePointer(metadata)
                    aggregates[index].key.swift_name_resolver = resolveHeapPprofReusableTestName
                    aggregates[index].key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
                    aggregates[index].key.frame_count = 1
                    aggregates[index].key.frames.0 = UInt64(index + 1)
                }
                aggregates.withUnsafeBufferPointer { samples in
                    var view = dd_memory_aggregation_view_t(samples: samples.baseAddress, count: samples.count)
                    XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
                }
                XCTAssertEqual(metadata.pointee.calls, 3)
            }
        }

        let decoded = try decode()
        XCTAssertEqual(decoded.samples.map { $0.labels["allocation class"] }, ["A", "B", "A"])
        XCTAssertEqual(decoded.strings.filter { $0 == "A" }.count, 1)
        XCTAssertEqual(decoded.strings.filter { $0 == "B" }.count, 1)
    }

    func testRepeatedLongClassNamesFitWithinThePayloadLimit() throws {
        dd_memory_pprof_encoder_destroy(encoder)
        encoder = nil
        encoder = try XCTUnwrap(dd_memory_pprof_encoder_create(2_048))
        let name = String(repeating: "A", count: Int(DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES))

        try encodeSwiftName(Array(name.utf8).map { CChar(bitPattern: $0) }, sampleCount: 8)

        let decoded = try decode()
        XCTAssertEqual(decoded.samples.count, 8)
        XCTAssertTrue(decoded.samples.allSatisfy { $0.labels["allocation class"] == name })
        XCTAssertEqual(decoded.strings.filter { $0 == name }.count, 1)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).limit_failures, 0)
    }

    func testClassNameStringsResetBetweenProfiles() throws {
        for (name, previousName) in [("First", "Second"), ("Second", "First"), ("First", "Second")] {
            try encodeSwiftName(Array(name.utf8).map { CChar(bitPattern: $0) })

            let decoded = try decode()
            XCTAssertEqual(decoded.samples.first?.labels["allocation class"], name)
            XCTAssertEqual(decoded.strings.filter { $0 == name }.count, 1)
            XCTAssertFalse(decoded.strings.contains(previousName))
        }
    }

    func testKnownProgramCounterHasBinaryMappingAndBuildID() throws {
        let symbol = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc"))
        let address = UInt64(UInt(bitPattern: symbol))
        try record(address: 0x10000, size: 16, weight: 1, className: "Mapped", frames: [address, address])
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        let decoded = try encodeClosedWindow()
        XCTAssertEqual(decoded.samples.first?.frames, [address, address])
        XCTAssertEqual(decoded.locationCount, 1)
        XCTAssertEqual(decoded.mappingCount, 1)
        XCTAssertEqual(decoded.buildIDs.count, 1)
        XCTAssertEqual(decoded.buildIDs.first?.count, 36)
        XCTAssertFalse(try XCTUnwrap(decoded.filenames.first).isEmpty)
        XCTAssertTrue(decoded.samples.allSatisfy { $0.mappingIDs.allSatisfy { $0 != 0 } })
    }

    func testHeapMappingsShareCachedMetadataAcrossWindowsAndCPUProfilerRestarts() throws {
        dd_profiler_destroy()
        defer { dd_profiler_destroy() }
        dd_memory_pprof_encoder_destroy(encoder)
        encoder = nil
        encoder = try XCTUnwrap(dd_memory_pprof_encoder_create(Int(DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES)))
        let cache = try XCTUnwrap(binary_image_cache_shared_for_testing())
        let symbol = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc"))
        let otherSymbol = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "calloc"))
        let address = UInt64(UInt(bitPattern: symbol))
        let otherAddress = UInt64(UInt(bitPattern: otherSymbol))
        var firstImage = binary_image_t()
        XCTAssertTrue(binary_image_lookup_pc(&firstImage, symbol))
        defer { binary_image_destroy(&firstImage) }
        var otherImage = binary_image_t()
        XCTAssertTrue(binary_image_lookup_pc(&otherImage, otherSymbol))
        defer { binary_image_destroy(&otherImage) }
        XCTAssertEqual(firstImage.load_address, otherImage.load_address)
        XCTAssertEqual(
            String(cString: try XCTUnwrap(firstImage.filename)),
            String(cString: try XCTUnwrap(otherImage.filename))
        )
        let expectedFilename = String(cString: try XCTUnwrap(firstImage.filename))
        let expectedBuildID = UUID(uuid: firstImage.uuid).uuidString

        try record(address: 0x10000, size: 16, weight: 1, className: "Mapped", frames: [address])
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        let heapOnly = try encodeClosedWindow()
        XCTAssertEqual(heapOnly.filenames, [expectedFilename])
        XCTAssertEqual(heapOnly.buildIDs, [expectedBuildID])
        XCTAssertTrue(heapOnly.samples.allSatisfy { $0.mappingIDs == [1] })

        for _ in 0..<2 {
            XCTAssertEqual(dd_profiler_start(), 1)
            dd_profiler_stop()
            dd_profiler_destroy()
            XCTAssertEqual(cache, binary_image_cache_shared_for_testing())

            XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
            let afterCPU = try encodeClosedWindow()
            XCTAssertEqual(afterCPU.filenames, heapOnly.filenames)
            XCTAssertEqual(afterCPU.buildIDs, heapOnly.buildIDs)
            XCTAssertEqual(afterCPU.samples.first?.values, [0, 0, 1, 16])
        }

        try record(address: 0x20000, size: 32, weight: 1, className: "Mapped", frames: [otherAddress])
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        let sameImage = try encodeClosedWindow()
        XCTAssertEqual(sameImage.locationCount, 2)
        XCTAssertEqual(sameImage.mappingCount, 1)
        XCTAssertEqual(sameImage.filenames, [expectedFilename])
        XCTAssertEqual(sameImage.buildIDs, [expectedBuildID])
        XCTAssertTrue(sameImage.samples.allSatisfy { $0.mappingIDs == [1] })
    }

    func testSaturatesFinalIntegerConversionAndCountsSaturatedValues() throws {
        var aggregate = dd_memory_aggregate_t()
        aggregate.alloc_objects = .infinity
        aggregate.alloc_space = Double.greatestFiniteMagnitude
        aggregate.inuse_objects = 1.49
        aggregate.inuse_space = 1.5
        var view = dd_memory_aggregation_view_t()
        let success = withUnsafePointer(to: &aggregate) {
            view.samples = $0
            view.count = 1
            return dd_memory_pprof_encoder_encode(encoder, &view, 0, 0)
        }
        XCTAssertTrue(success)
        XCTAssertEqual(try decode().samples.first?.values, [Int64.max, Int64.max, 1, 2])
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).saturated_values, 2)
    }

    func testInvalidInputsClearPreviousOutputAndNeverPublishPartialProfiles() throws {
        try record(address: 0x10000, size: 16, weight: 1, className: "Valid", frames: [])
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        _ = try encodeClosedWindow()
        XCTAssertGreaterThan(dd_memory_pprof_encoder_view(encoder).size, 0)
        var view = dd_memory_allocation_window_view(window)
        XCTAssertFalse(dd_memory_pprof_encoder_encode(encoder, &view, -1, 0))
        XCTAssertEqual(dd_memory_pprof_encoder_view(encoder).size, 0)

        for value in [Double.nan, -1, -Double.infinity] {
            var aggregate = dd_memory_aggregate_t()
            aggregate.alloc_objects = value
            XCTAssertFalse(withUnsafePointer(to: &aggregate) {
                view.samples = $0
                view.count = 1
                return dd_memory_pprof_encoder_encode(encoder, &view, 0, 0)
            })
            XCTAssertEqual(dd_memory_pprof_encoder_view(encoder).size, 0)
        }
        view.samples = nil
        view.count = 1
        XCTAssertFalse(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
        XCTAssertFalse(dd_memory_pprof_encoder_encode(encoder, nil, 0, 0))
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).invalid_profiles, 6)
    }

    func testEmptyProfilesAreSkippedAndPayloadLimitIsEnforced() throws {
        var empty = dd_memory_aggregation_view_t()
        XCTAssertFalse(dd_memory_pprof_encoder_encode(encoder, &empty, 0, 0))
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).empty_profiles_skipped, 1)
        XCTAssertEqual(dd_memory_pprof_encoder_view(encoder).size, 0)

        let bounded = try XCTUnwrap(dd_memory_pprof_encoder_create(32))
        defer { dd_memory_pprof_encoder_destroy(bounded) }
        var aggregate = dd_memory_aggregate_t()
        aggregate.alloc_objects = 1
        var view = dd_memory_aggregation_view_t()
        XCTAssertFalse(withUnsafePointer(to: &aggregate) {
            view.samples = $0
            view.count = 1
            return dd_memory_pprof_encoder_encode(bounded, &view, 0, 0)
        })
        XCTAssertEqual(dd_memory_pprof_encoder_view(bounded).size, 0)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(bounded).limit_failures, 1)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(bounded).max_payload_bytes, 32)
    }

    func testRejectsSampleCountBeyondBoundBeforeReadingRecords() throws {
        var aggregate = dd_memory_aggregate_t()
        var view = dd_memory_aggregation_view_t()
        XCTAssertFalse(withUnsafePointer(to: &aggregate) {
            view.samples = $0
            view.count = Int(DD_MEMORY_AGGREGATION_CAPACITY) + 1
            return dd_memory_pprof_encoder_encode(encoder, &view, 0, 0)
        })
        XCTAssertEqual(dd_memory_pprof_encoder_view(encoder).size, 0)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).limit_failures, 1)
    }

    func testNullAndInvalidCreationInputsAreSafe() {
        XCTAssertNil(dd_memory_pprof_encoder_create(0))
        XCTAssertNil(dd_memory_pprof_encoder_create(Int(DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES) + 1))
        XCTAssertFalse(dd_memory_pprof_encoder_encode(nil, nil, 0, 0))
        XCTAssertEqual(dd_memory_pprof_encoder_view(nil).size, 0)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(nil).storage_bytes, 0)
        dd_memory_pprof_encoder_destroy(nil)
    }

    func testSwiftNamesAreCopiedImmediatelyAndInvalidNamesAreOmitted() throws {
        try encodeSwiftName(Array("TemporarySwiftType".utf8).map { CChar(bitPattern: $0) })
        XCTAssertEqual(try decode().samples.first?.labels["allocation class"], "TemporarySwiftType")
        XCTAssertEqual(try decode().samples.first?.labels["source"], "swift")

        try encodeSwiftName([65, 0, 66])
        XCTAssertNil(try decode().samples.first?.labels["allocation class"])
        try encodeSwiftName([65], length: UInt64(DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES) + 1)
        XCTAssertNil(try decode().samples.first?.labels["allocation class"])
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).omitted_class_names, 2)
    }

    func testPayloadOverflowAfterPackingASampleDiscardsOutputAndAllowsRetry() throws {
        let className = strdup("RetriedClass")!
        defer { free(className) }
        var aggregate = dd_memory_aggregate_t()
        aggregate.alloc_objects = 1
        aggregate.key.class_name = UnsafePointer(className)
        aggregate.key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
        var view = dd_memory_aggregation_view_t()
        let singleSize = withUnsafePointer(to: &aggregate) { sample in
            view.samples = sample
            view.count = 1
            XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
            return dd_memory_pprof_encoder_view(encoder).size
        }
        let bounded = try XCTUnwrap(dd_memory_pprof_encoder_create(singleSize))
        defer { dd_memory_pprof_encoder_destroy(bounded) }
        let twoSamples = [aggregate, aggregate]
        twoSamples.withUnsafeBufferPointer { samples in
            view.samples = samples.baseAddress
            view.count = 2
            XCTAssertFalse(dd_memory_pprof_encoder_encode(bounded, &view, 0, 0))
            XCTAssertEqual(dd_memory_pprof_encoder_view(bounded).size, 0)
            view.count = 1
            XCTAssertTrue(dd_memory_pprof_encoder_encode(bounded, &view, 0, 0))
        }
        let encoded = dd_memory_pprof_encoder_view(bounded)
        let decoded = try XCTUnwrap(perftools__profiles__profile__unpack(nil, encoded.size, encoded.data))
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        XCTAssertEqual(decoded.pointee.n_sample, 1)
        let strings = (0..<decoded.pointee.n_string_table).map { String(cString: decoded.pointee.string_table[$0]!) }
        XCTAssertEqual(strings.filter { $0 == "RetriedClass" }.count, 1)
        let sample = decoded.pointee.sample[0]!.pointee
        let labels = (0..<sample.n_label).map { sample.label[$0]!.pointee }
        let classLabel = try XCTUnwrap(labels.first { strings[Int($0.key)] == "allocation class" })
        XCTAssertEqual(strings[Int(classLabel.str)], "RetriedClass")
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(bounded).limit_failures, 1)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(bounded).encoded_profiles, 1)
    }

    func testUniqueLocationLimitDiscardsTheWholeProfileAndAllowsRetry() throws {
        let maximum = Int(DD_MEMORY_PPROF_MAX_UNIQUE_LOCATIONS)
        let depth = Int(DD_MEMORY_LIVE_SET_MAX_FRAMES)
        var aggregates = [dd_memory_aggregate_t](repeating: dd_memory_aggregate_t(), count: maximum / depth + 1)
        for index in aggregates.indices {
            aggregates[index].alloc_objects = 1
            let count = index == aggregates.count - 1 ? 1 : depth
            aggregates[index].key.frame_count = UInt32(count)
            withUnsafeMutableBytes(of: &aggregates[index].key.frames) { storage in
                for frame in 0..<count {
                    storage.storeBytes(
                        of: UInt64(index * depth + frame + 1),
                        toByteOffset: frame * MemoryLayout<UInt64>.size,
                        as: UInt64.self
                    )
                }
            }
        }
        aggregates.withUnsafeBufferPointer { samples in
            var view = dd_memory_aggregation_view_t(samples: samples.baseAddress, count: samples.count)
            XCTAssertFalse(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
            XCTAssertEqual(dd_memory_pprof_encoder_view(encoder).size, 0)
            XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).unresolved_locations, UInt64(maximum))
            view.count = 1
            XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
        }
        XCTAssertEqual(try decode().locationCount, depth)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).limit_failures, 1)
    }

    func testLocationProbeLimitDiscardsTheWholeProfileAndAllowsRetry() throws {
        // Inverting the SplitMix64 finalizer for 1...65 shifted left by 17
        // gives distinct PCs in bucket zero of the 131,072-entry location index.
        // The 65th PC exceeds the 64-probe bound while overall capacity remains available.
        let collidingPCs: [UInt64] = [
            0x670c_5c2e_6489_489f, 0x28b7_267c_956e_0dbe, 0xd452_a34a_578a_6c6a, 0x516e_4cf9_2adc_1b7c,
            0xb361_591a_2675_3789, 0x9a21_cfc7_fa52_4810, 0x3942_3d25_462c_510b, 0x39ba_b508_fb31_359a,
            0xf47a_b701_38bd_83df, 0xa302_5f2e_5cb9_68f2, 0xee5f_ed1b_7c0f_0320, 0xcb21_baa1_483a_9422,
            0x5058_dcd3_74b7_8002, 0x6401_037f_5b98_f238, 0x667c_d379_d638_f5d3, 0x7375_6a11_f662_6b35,
            0x27a2_cc5d_527d_ab05, 0x4393_dc23_16bf_933a, 0xf091_d605_7bf7_09c9, 0x4604_be58_b972_d1f4,
            0x4c56_f239_7988_78cd, 0x18ff_872c_e04e_c790, 0x21e5_1655_4406_2971, 0x9643_7546_9075_2854,
            0x626f_7a84_d183_274c, 0x4613_4b89_3d2a_ecba, 0x4c8e_c1f7_83d4_9bb3, 0x5ee0_2215_adcb_1845,
            0xb2f2_41ba_d25b_766a, 0xbe76_3026_dd33_e46a, 0x902c_a95a_9340_78ed, 0xe6ea_d423_ecc4_d66b,
            0x5e74_14b0_5df3_42d8, 0xf4a7_2a9c_8137_ba92, 0x4f35_4b33_19d3_8d2e, 0x1e05_d35b_08e4_1a99,
            0xc4bf_16ca_b3fc_100c, 0x8685_3df3_370a_8874, 0xda96_949e_be6c_61ec, 0x8c09_7cb1_72e5_a3e9,
            0xb4ea_30aa_3cdb_9a3a, 0xf34c_528f_1ad8_ce6c, 0x8afc_1d2b_ba0b_c4a0, 0xc8dd_2973_6507_e302,
            0x0dbc_e4e8_35d3_b995, 0xe92b_be8c_e44c_467b, 0x7ca9_e158_7846_9772, 0x68c6_9785_28db_3931,
            0x1bbc_1857_6a14_a100, 0x5bbd_1020_817b_6bc5, 0xbb35_4e9e_17c3_a168, 0xc866_4408_6207_e1e4,
            0xeb37_dc04_e448_de20, 0x991d_83ef_07a9_3766, 0xaa0f_58a6_7910_0108, 0x185e_b245_93a3_8d30,
            0xa0f0_e453_bd9e_a092, 0x65e4_8371_a4b6_ecc4, 0x71b8_49fb_45ab_3aed, 0x224d_f22c_8aa3_ed50,
            0xf278_665e_d227_56f6, 0x2059_52b1_2680_f1ca, 0xb516_a650_9d6b_f0da, 0x0a15_553b_cffb_2ebe,
            0x7829_dcd9_ca34_b1b3,
        ]
        var aggregates = [dd_memory_aggregate_t](repeating: dd_memory_aggregate_t(), count: collidingPCs.count)
        for index in aggregates.indices {
            aggregates[index].alloc_objects = 1
            aggregates[index].key.frame_count = 1
            aggregates[index].key.frames.0 = collidingPCs[index]
        }
        aggregates.withUnsafeBufferPointer { samples in
            var view = dd_memory_aggregation_view_t(samples: samples.baseAddress, count: 1)
            XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
            XCTAssertGreaterThan(dd_memory_pprof_encoder_view(encoder).size, 0)

            view.count = samples.count
            XCTAssertFalse(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
            XCTAssertEqual(dd_memory_pprof_encoder_view(encoder).size, 0)
            XCTAssertNil(dd_memory_pprof_encoder_view(encoder).data)

            view.count = samples.count - 1
            XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
        }

        let decoded = try decode()
        XCTAssertEqual(decoded.samples.count, 64)
        XCTAssertEqual(decoded.samples.map { $0.frames }, collidingPCs.prefix(64).map { [$0] })
        XCTAssertEqual(decoded.locationCount, 64)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).limit_failures, 1)
        XCTAssertEqual(dd_memory_pprof_encoder_diagnostics(encoder).encoded_profiles, 2)
    }

    private func encodeSwiftName(_ bytes: [CChar], length: UInt64? = nil, sampleCount: Int = 1) throws {
        bytes.withUnsafeBufferPointer { name in
            var context = HeapPprofNameContext(data: name.baseAddress, length: length ?? UInt64(name.count))
            withUnsafeMutablePointer(to: &context) { metadata in
                var aggregates = [dd_memory_aggregate_t](repeating: dd_memory_aggregate_t(), count: sampleCount)
                for index in aggregates.indices {
                    aggregates[index].key.swift_metadata = OpaquePointer(metadata)
                    aggregates[index].key.swift_name_resolver = resolveHeapPprofTestName
                    aggregates[index].key.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
                    aggregates[index].key.frame_count = 1
                    aggregates[index].key.frames.0 = UInt64(index + 1)
                    aggregates[index].alloc_objects = 1
                }
                aggregates.withUnsafeBufferPointer { samples in
                    var view = dd_memory_aggregation_view_t(samples: samples.baseAddress, count: samples.count)
                    XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 0, 0))
                }
                XCTAssertEqual(metadata.pointee.calls, sampleCount)
            }
        }
    }

    private func record(
        address: Int,
        size: UInt64,
        weight: Double,
        className: String,
        frames: [UInt64],
        source: dd_memory_live_sample_source_t = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
    ) throws {
        var sample = dd_memory_live_sample_t()
        sample.address = UnsafeRawPointer(bitPattern: address)
        sample.size = size
        sample.weight = weight
        sample.frame_count = UInt32(frames.count)
        sample.source = source
        withUnsafeMutableBytes(of: &sample.frames) { storage in
            for (index, frame) in frames.enumerated() {
                storage.storeBytes(of: frame, toByteOffset: index * MemoryLayout<UInt64>.size, as: UInt64.self)
            }
        }
        let result = className.withCString {
            sample.class_name = $0
            return dd_memory_allocation_window_record(window, generation, &sample)
        }
        XCTAssertEqual(result, DD_MEMORY_LIVE_SET_INSERTED)
    }

    private func encodeClosedWindow() throws -> DecodedHeapProfile {
        var view = dd_memory_allocation_window_view(window)
        XCTAssertTrue(dd_memory_pprof_encoder_encode(encoder, &view, 123_000, 60_000))
        return try decode()
    }

    private func decode() throws -> DecodedHeapProfile {
        let encoded = dd_memory_pprof_encoder_view(encoder)
        let decoded = try XCTUnwrap(perftools__profiles__profile__unpack(nil, encoded.size, encoded.data))
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        let profile = decoded.pointee
        let strings = (0..<profile.n_string_table).map { String(cString: profile.string_table[$0]!) }
        let types = (0..<profile.n_sample_type).map { index -> (String, String) in
            let type = profile.sample_type[index]!.pointee
            return (strings[Int(type.type)], strings[Int(type.unit)])
        }
        var frames: [UInt64: (UInt64, UInt64)] = [:]
        for index in 0..<profile.n_location {
            let location = profile.location[index]!.pointee
            frames[location.id] = (location.address, location.mapping_id)
        }
        let samples = (0..<profile.n_sample).map { index -> DecodedHeapSample in
            let sample = profile.sample[index]!.pointee
            let values = Array(UnsafeBufferPointer(start: sample.value, count: sample.n_value))
            var labels: [String: String] = [:]
            for labelIndex in 0..<sample.n_label {
                let label = sample.label[labelIndex]!.pointee
                labels[strings[Int(label.key)]] = strings[Int(label.str)]
            }
            let locations = Array(UnsafeBufferPointer(start: sample.location_id, count: sample.n_location_id))
            return DecodedHeapSample(
                values: values,
                labels: labels,
                frames: locations.map { frames[$0]?.0 ?? UInt64.max },
                mappingIDs: locations.map { frames[$0]?.1 ?? UInt64.max }
            )
        }
        let mappings = (0..<profile.n_mapping).map { profile.mapping[$0]!.pointee }
        return DecodedHeapProfile(
            strings: strings,
            types: types,
            samples: samples,
            periodType: strings[Int(profile.period_type!.pointee.type)],
            periodUnit: strings[Int(profile.period_type!.pointee.unit)],
            period: profile.period,
            defaultType: strings[Int(profile.default_sample_type)],
            time: profile.time_nanos,
            duration: profile.duration_nanos,
            locationCount: profile.n_location,
            mappingCount: profile.n_mapping,
            buildIDs: mappings.map { strings[Int($0.build_id)] },
            filenames: mappings.map { strings[Int($0.filename)] }
        )
    }
}

private struct DecodedHeapSample {
    let values: [Int64]
    let labels: [String: String]
    let frames: [UInt64]
    let mappingIDs: [UInt64]
}

private struct HeapPprofNameContext {
    let data: UnsafePointer<CChar>?
    let length: UInt64
    var calls: Int = 0
}

private func resolveHeapPprofTestName(_ metadata: OpaquePointer?) -> dd_swift_class_name_t {
    guard let metadata else {
        return dd_swift_class_name_t()
    }
    let context = UnsafeMutableRawPointer(metadata).assumingMemoryBound(to: HeapPprofNameContext.self)
    context.pointee.calls += 1
    return dd_swift_class_name_t(data: context.pointee.data, length: context.pointee.length)
}

private struct HeapPprofReusableNameContext {
    let data: UnsafeMutablePointer<CChar>
    var calls: Int = 0
}

private func resolveHeapPprofReusableTestName(_ metadata: OpaquePointer?) -> dd_swift_class_name_t {
    guard let metadata else {
        return dd_swift_class_name_t()
    }
    let context = UnsafeMutableRawPointer(metadata).assumingMemoryBound(to: HeapPprofReusableNameContext.self)
    context.pointee.calls += 1
    context.pointee.data.pointee = context.pointee.calls == 2 ? 66 : 65
    return dd_swift_class_name_t(data: UnsafePointer(context.pointee.data), length: 1)
}

private struct DecodedHeapProfile {
    let strings: [String]
    let types: [(String, String)]
    let samples: [DecodedHeapSample]
    let periodType: String
    let periodUnit: String
    let period: Int64
    let defaultType: String
    let time: Int64
    let duration: Int64
    let locationCount: Int
    let mappingCount: Int
    let buildIDs: [String]
    let filenames: [String]
}
#endif // !os(watchOS)
