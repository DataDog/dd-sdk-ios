/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest
import DatadogMachProfiler.Testing

final class MemoryAllocationWindowTests: XCTestCase {
    private var window: OpaquePointer?
    private var generation: UInt64 = 0

    override func setUp() {
        super.setUp()
        window = dd_memory_allocation_window_create()
        XCTAssertNotNil(window)
        generation = dd_memory_allocation_window_start(window)
        XCTAssertNotEqual(generation, 0)
    }

    override func tearDown() {
        dd_memory_allocation_window_stop(window)
        dd_memory_allocation_window_destroy(window)
        window = nil
        super.tearDown()
    }

    func testTransientObjectsContributeOnlyToAllocationTotals() {
        XCTAssertEqual(record(sample(at: 0x10000, size: 100, weight: 1.5)), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertTrue(remove(0x10000))

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        assertTotals(aggregates, allocObjects: 1.5, allocSpace: 150, inuseObjects: 0, inuseSpace: 0)
    }

    func testRetainedObjectsContributeToBothTotalsAndSurviveSubsequentWindows() {
        XCTAssertEqual(record(sample(at: 0x10000, size: 100, weight: 1.5)), DD_MEMORY_LIVE_SET_INSERTED)

        let firstWindow = closeWindow()
        XCTAssertEqual(firstWindow.count, 1)
        assertTotals(firstWindow, allocObjects: 1.5, allocSpace: 150, inuseObjects: 1.5, inuseSpace: 150)
        for _ in 0..<3 {
            let nextWindow = closeWindow()
            XCTAssertEqual(nextWindow.count, 1)
            assertTotals(nextWindow, allocObjects: 0, allocSpace: 0, inuseObjects: 1.5, inuseSpace: 150)
        }

        XCTAssertTrue(remove(0x10000))
        XCTAssertTrue(closeWindow().isEmpty)
    }

    func testTransientAndRetainedObjectsAggregateIndependentlyWithFractionalWeights() {
        XCTAssertEqual(record(sample(at: 0x10000, size: 3, weight: 0.4)), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertTrue(remove(0x10000))
        XCTAssertEqual(record(sample(at: 0x20000, size: 7, weight: 0.4)), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertTrue(remove(0x20000))
        XCTAssertEqual(record(sample(at: 0x30000, size: 11, weight: 0.4)), DD_MEMORY_LIVE_SET_INSERTED)

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        assertTotals(aggregates, allocObjects: 1.2, allocSpace: 8.4, inuseObjects: 0.4, inuseSpace: 4.4)
        assertTotals(closeWindow(), allocObjects: 0, allocSpace: 0, inuseObjects: 0.4, inuseSpace: 4.4)
    }

    func testAddressReuseCountsEachAllocationWhileKeepingOnlyCurrentLifetimeLive() {
        for size in [UInt64(10), 20] {
            XCTAssertEqual(record(sample(at: 0x10000, size: size)), DD_MEMORY_LIVE_SET_INSERTED)
            XCTAssertTrue(remove(0x10000))
        }
        XCTAssertEqual(record(sample(at: 0x10000, size: 30)), DD_MEMORY_LIVE_SET_INSERTED)

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        assertTotals(aggregates, allocObjects: 3, allocSpace: 60, inuseObjects: 1, inuseSpace: 30)
    }

    func testLiveAdmissionOverflowDoesNotEraseAllocationActivity() {
        let addresses = collidingAddresses(count: Int(DD_MEMORY_LIVE_SET_MAX_PROBE) + 1)
        XCTAssertEqual(addresses.count, Int(DD_MEMORY_LIVE_SET_MAX_PROBE) + 1)
        for address in addresses.dropLast() {
            XCTAssertEqual(record(sample(at: address, size: 10)), DD_MEMORY_LIVE_SET_INSERTED)
        }
        guard let rejectedAddress = addresses.last else {
            return
        }
        XCTAssertEqual(record(sample(at: rejectedAddress, size: 100)), DD_MEMORY_LIVE_SET_DROPPED)

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        let admittedCount = Double(DD_MEMORY_LIVE_SET_MAX_PROBE)
        assertTotals(
            aggregates,
            allocObjects: admittedCount + 1,
            allocSpace: admittedCount * 10 + 100,
            inuseObjects: admittedCount,
            inuseSpace: admittedCount * 10
        )
        let diagnostics = dd_memory_allocation_window_closed_diagnostics(window)
        XCTAssertEqual(diagnostics.recorded_allocations, UInt64(addresses.count))
        XCTAssertEqual(diagnostics.dropped_alloc_records, 0)
        XCTAssertEqual(diagnostics.live_set.dropped_samples, 1)
        XCTAssertTrue(diagnostics.live_set.reached_admission_limit)
    }

    func testRecorderOverflowStillAdmitsLiveObjectsAndCountersResetAtClose() {
        let capacity = Int(DD_MEMORY_ALLOCATION_WINDOW_CAPACITY)
        for _ in 0..<capacity {
            XCTAssertEqual(record(sample(at: 0x10000, size: 2)), DD_MEMORY_LIVE_SET_INSERTED)
            XCTAssertTrue(remove(0x10000))
        }
        XCTAssertEqual(record(sample(at: 0x20000, size: 7)), DD_MEMORY_LIVE_SET_INSERTED)

        let current = dd_memory_allocation_window_diagnostics(window)
        XCTAssertEqual(current.capacity, UInt64(capacity))
        XCTAssertEqual(current.recorded_allocations, UInt64(capacity))
        XCTAssertEqual(current.peak_recorded_allocations, UInt64(capacity))
        XCTAssertEqual(current.dropped_alloc_records, 1)
        XCTAssertEqual(current.live_set.occupancy, 1)
        XCTAssertEqual(current.live_set.dropped_samples, 0)
        XCTAssertGreaterThan(current.storage_bytes, 0)

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        assertTotals(
            aggregates,
            allocObjects: Double(capacity),
            allocSpace: Double(capacity * 2),
            inuseObjects: 1,
            inuseSpace: 7
        )
        let closed = dd_memory_allocation_window_closed_diagnostics(window)
        XCTAssertEqual(closed.recorded_allocations, UInt64(capacity))
        XCTAssertEqual(closed.peak_recorded_allocations, UInt64(capacity))
        XCTAssertEqual(closed.dropped_alloc_records, 1)
        XCTAssertEqual(closed.live_set.occupancy, 1)

        let next = dd_memory_allocation_window_diagnostics(window)
        XCTAssertEqual(next.recorded_allocations, 0)
        XCTAssertEqual(next.peak_recorded_allocations, 0)
        XCTAssertEqual(next.dropped_alloc_records, 0)
        XCTAssertEqual(next.live_set.occupancy, 1)
        assertTotals(closeWindow(), allocObjects: 0, allocSpace: 0, inuseObjects: 1, inuseSpace: 7)
        let emptyWindow = dd_memory_allocation_window_closed_diagnostics(window)
        XCTAssertEqual(emptyWindow.recorded_allocations, 0)
        XCTAssertEqual(emptyWindow.peak_recorded_allocations, 0)
        XCTAssertEqual(emptyWindow.dropped_alloc_records, 0)
    }

    func testAggregationKeyUsesClassBytesStackAndSource() {
        var firstName = Array("SameClass".utf8CString)
        var secondName = Array("SameClass".utf8CString)
        firstName.withUnsafeMutableBufferPointer { first in
            secondName.withUnsafeMutableBufferPointer { second in
                XCTAssertNotEqual(first.baseAddress, second.baseAddress)
                for (index, name) in [first.baseAddress, second.baseAddress].enumerated() {
                    var entry = sample(at: UInt(0x10000 + index * 16), size: 1)
                    entry.class_name = UnsafePointer(name)
                    entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
                    entry.frame_count = 1
                    entry.frames.0 = 10
                    XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
                }
                var entry = sample(at: 0x20000, size: 1)
                entry.class_name = UnsafePointer(first.baseAddress)
                entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
                entry.frame_count = 1
                entry.frames.0 = 20
                XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)

                entry.address = UnsafeRawPointer(bitPattern: 0x30000)
                entry.frames.0 = 10
                entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_UNKNOWN
                XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
            }
        }
        "DifferentClass".withCString { name in
            var entry = sample(at: 0x40000, size: 1)
            entry.class_name = name
            entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
            entry.frame_count = 1
            entry.frames.0 = 10
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
        }

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 4)
        XCTAssertEqual(aggregates.map(\.alloc_objects).sorted(), [1, 1, 1, 2])
        assertTotals(aggregates, allocObjects: 5, allocSpace: 5, inuseObjects: 5, inuseSpace: 5)
    }

    func testAggregationPreservesMaximumDisjointAllocationAndLiveKeys() {
        let liveCapacity = Int(DD_MEMORY_LIVE_SET_CAPACITY)
        var addresses = Array(repeating: UInt(0), count: liveCapacity)
        var remaining = liveCapacity
        for index in 0..<1_000_000 {
            let address = UInt(0x10_0000 + index * 16)
            let bucket = dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: address))
            if addresses[bucket] == 0 {
                addresses[bucket] = address
                remaining -= 1
                if remaining == 0 {
                    break
                }
            }
        }
        XCTAssertEqual(remaining, 0)
        guard remaining == 0 else {
            return
        }
        for (index, address) in addresses.enumerated() {
            var entry = sample(at: address, size: 2)
            entry.frame_count = 1
            entry.frames.0 = UInt64(index)
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        XCTAssertEqual(closeWindow().count, liveCapacity)

        let allocationCapacity = Int(DD_MEMORY_ALLOCATION_WINDOW_CAPACITY)
        for index in 0..<allocationCapacity {
            var entry = sample(at: 0x2000_0000, size: 3)
            entry.frame_count = 1
            entry.frames.0 = UInt64(liveCapacity + index)
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_DROPPED)
        }
        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, Int(DD_MEMORY_AGGREGATION_CAPACITY))
        XCTAssertEqual(aggregates.filter { $0.alloc_objects > 0 }.count, allocationCapacity)
        XCTAssertEqual(aggregates.filter { $0.inuse_objects > 0 }.count, liveCapacity)
        assertTotals(
            aggregates,
            allocObjects: Double(allocationCapacity),
            allocSpace: Double(allocationCapacity * 3),
            inuseObjects: Double(liveCapacity),
            inuseSpace: Double(liveCapacity * 2)
        )
        let diagnostics = dd_memory_allocation_window_closed_diagnostics(window)
        XCTAssertEqual(diagnostics.dropped_alloc_records, 0)
        XCTAssertEqual(diagnostics.live_set.dropped_samples, UInt64(allocationCapacity))
    }

    func testRecorderAndClosedWindowOwnObjectiveCClassNames() throws {
        var name = Array("OriginalClass".utf8CString)
        name.withUnsafeMutableBufferPointer { bytes in
            var entry = sample(at: 0x10000, size: 5)
            entry.class_name = UnsafePointer(bytes.baseAddress)
            entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
            for index in bytes.indices.dropLast() {
                bytes[index] = 120
            }
        }

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        let aggregate = try XCTUnwrap(aggregates.first)
        XCTAssertEqual(String(cString: try XCTUnwrap(aggregate.key.class_name)), "OriginalClass")
        assertTotals(aggregates, allocObjects: 1, allocSpace: 5, inuseObjects: 1, inuseSpace: 5)

        "LaterClass".withCString { name in
            var entry = sample(at: 0x20000, size: 10)
            entry.class_name = name
            entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        XCTAssertTrue(remove(0x10000))
        dd_memory_allocation_window_stop(window)
        let view = dd_memory_allocation_window_view(window)
        XCTAssertEqual(view.count, 1)
        XCTAssertEqual(String(cString: try XCTUnwrap(view.samples?.pointee.key.class_name)), "OriginalClass")
    }

    func testOverlongClassNamesAreOmittedAndCountedInEachWindow() {
        let name = String(repeating: "x", count: Int(DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES))
        name.withCString { name in
            var entry = sample(at: 0x10000, size: 1)
            entry.class_name = name
            entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).omitted_class_names, 1)
        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 1)
        XCTAssertNil(aggregates.first?.key.class_name)
        XCTAssertEqual(dd_memory_allocation_window_closed_diagnostics(window).omitted_class_names, 1)
        XCTAssertEqual(dd_memory_allocation_window_closed_diagnostics(window).live_set.omitted_class_names, 1)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).omitted_class_names, 0)
    }

    func testSwiftMetadataDefinesClassIdentityWithoutResolvingNamesDuringRecordOrClose() {
        let resolverCalls = UnsafeMutablePointer<Int>.allocate(capacity: 2)
        resolverCalls.initialize(repeating: 0, count: 2)
        defer {
            resolverCalls.deinitialize(count: 2)
            resolverCalls.deallocate()
        }
        for (index, identity) in [0, 0, 1].enumerated() {
            var entry = sample(at: UInt(0x10000 + index * 16), size: 1)
            entry.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
            entry.swift_metadata = OpaquePointer(resolverCalls.advanced(by: identity))
            entry.swift_name_resolver = resolveAllocationWindowSwiftName
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        XCTAssertEqual(resolverCalls[0] + resolverCalls[1], 0)

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 2)
        XCTAssertEqual(aggregates.map(\.alloc_objects).sorted(), [1, 2])
        XCTAssertEqual(resolverCalls[0] + resolverCalls[1], 0)
        for aggregate in aggregates {
            _ = aggregate.key.swift_name_resolver?(aggregate.key.swift_metadata)
        }
        XCTAssertEqual(resolverCalls[0], 1)
        XCTAssertEqual(resolverCalls[1], 1)
    }

    func testZeroAndMaximumFrameDepthPreserveOnlyCapturedFrames() {
        for (index, unusedFrame) in [UInt64(10), 20].enumerated() {
            var entry = sample(at: UInt(0x10000 + index * 16), size: 1)
            entry.frames.0 = unusedFrame
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        var deepest = sample(at: 0x20000, size: 1)
        deepest.frame_count = UInt32(DD_MEMORY_LIVE_SET_MAX_FRAMES)
        withUnsafeMutableBytes(of: &deepest.frames) { bytes in
            let frames = bytes.bindMemory(to: UInt64.self)
            for index in frames.indices {
                frames[index] = UInt64(index + 1)
            }
        }
        XCTAssertEqual(record(deepest), DD_MEMORY_LIVE_SET_INSERTED)

        let aggregates = closeWindow()
        XCTAssertEqual(aggregates.count, 2)
        XCTAssertEqual(aggregates.map(\.key.frame_count).sorted(), [0, UInt32(DD_MEMORY_LIVE_SET_MAX_FRAMES)])
        XCTAssertEqual(aggregates.map(\.alloc_objects).sorted(), [1, 2])
        if var deepestResult = aggregates.first(where: { $0.key.frame_count == UInt32(DD_MEMORY_LIVE_SET_MAX_FRAMES) }) {
            withUnsafeBytes(of: &deepestResult.key.frames) { bytes in
                XCTAssertEqual(Array(bytes.bindMemory(to: UInt64.self)), (1...UInt64(DD_MEMORY_LIVE_SET_MAX_FRAMES)).map { $0 })
            }
        } else {
            XCTFail("Maximum-depth allocation was lost")
        }
    }

    func testFailedCloseRetainsAllocationRecordsAndRestartRejectsOldGeneration() {
        XCTAssertEqual(record(sample(at: 0x10000, size: 5)), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertFalse(dd_memory_allocation_window_close(window, generation + 1))
        XCTAssertEqual(dd_memory_allocation_window_view(window).count, 0)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).recorded_allocations, 1)
        assertTotals(closeWindow(), allocObjects: 1, allocSpace: 5, inuseObjects: 1, inuseSpace: 5)

        XCTAssertEqual(record(sample(at: 0x20000, size: 7)), DD_MEMORY_LIVE_SET_INSERTED)
        let oldGeneration = generation
        dd_memory_allocation_window_stop(window)
        XCTAssertFalse(dd_memory_allocation_window_close(window, oldGeneration))
        XCTAssertEqual(dd_memory_allocation_window_view(window).count, 0)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).recorded_allocations, 1)
        XCTAssertEqual(record(sample(at: 0x30000, size: 9)), DD_MEMORY_LIVE_SET_STALE_GENERATION)
        XCTAssertFalse(remove(0x10000))
        generation = dd_memory_allocation_window_start(window)
        XCTAssertNotEqual(generation, oldGeneration)
        var staleEntry = sample(at: 0x40000, size: 11)
        XCTAssertEqual(
            dd_memory_allocation_window_record(window, oldGeneration, &staleEntry),
            DD_MEMORY_LIVE_SET_STALE_GENERATION
        )
        XCTAssertFalse(dd_memory_allocation_window_remove(window, oldGeneration, staleEntry.address))
        XCTAssertTrue(closeWindow().isEmpty)
        let diagnostics = dd_memory_allocation_window_diagnostics(window)
        XCTAssertEqual(diagnostics.recorded_allocations, 0)
        XCTAssertEqual(diagnostics.dropped_alloc_records, 0)
        XCTAssertEqual(diagnostics.live_set.occupancy, 0)
    }

    func testInvalidSamplesDoNotContributeToEitherTotal() {
        let valid = sample(at: 0x10000, size: 1)
        var invalidSamples: [dd_memory_live_sample_t] = []
        for address in [UInt(0), 1] {
            var entry = valid
            entry.address = UnsafeRawPointer(bitPattern: address)
            invalidSamples.append(entry)
        }
        var zeroSize = valid
        zeroSize.size = 0
        invalidSamples.append(zeroSize)
        for weight in [0, -1, Double.infinity, -Double.infinity, Double.nan] {
            var entry = valid
            entry.weight = weight
            invalidSamples.append(entry)
        }
        var tooDeep = valid
        tooDeep.frame_count = UInt32(DD_MEMORY_LIVE_SET_MAX_FRAMES + 1)
        invalidSamples.append(tooDeep)
        var missingResolver = valid
        missingResolver.swift_metadata = OpaquePointer(bitPattern: 0x10)
        invalidSamples.append(missingResolver)
        var missingMetadata = valid
        missingMetadata.swift_name_resolver = resolveAllocationWindowSwiftName
        invalidSamples.append(missingMetadata)
        for entry in invalidSamples {
            XCTAssertEqual(record(entry), DD_MEMORY_LIVE_SET_INVALID_SAMPLE)
        }
        var entry = valid
        XCTAssertEqual(dd_memory_allocation_window_record(nil, generation, &entry), DD_MEMORY_LIVE_SET_INVALID_SAMPLE)
        XCTAssertEqual(dd_memory_allocation_window_record(window, generation, nil), DD_MEMORY_LIVE_SET_INVALID_SAMPLE)
        XCTAssertFalse(dd_memory_allocation_window_remove(window, generation, nil))
        XCTAssertTrue(closeWindow().isEmpty)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).recorded_allocations, 0)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).live_set.occupancy, 0)
    }

    func testNullWindowLifecycleAndViewsAreSafe() {
        XCTAssertEqual(dd_memory_allocation_window_start(nil), 0)
        dd_memory_allocation_window_stop(nil)
        dd_memory_allocation_window_destroy(nil)
        XCTAssertFalse(dd_memory_allocation_window_close(nil, generation))
        XCTAssertFalse(dd_memory_allocation_window_remove(nil, generation, UnsafeRawPointer(bitPattern: 0x10000)))
        XCTAssertEqual(dd_memory_allocation_window_view(nil).count, 0)
        XCTAssertNil(dd_memory_allocation_window_view(nil).samples)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(nil).recorded_allocations, 0)
        XCTAssertEqual(dd_memory_allocation_window_closed_diagnostics(nil).recorded_allocations, 0)
    }

    func testConcurrentRecordingRemovalAndClosingAccountForEveryAllocation() throws {
        let handle = AllocationWindowHandle(window: try XCTUnwrap(window), generation: generation)
        let workerCount = 8
        let cyclesPerWorker = Int(DD_MEMORY_ALLOCATION_WINDOW_CAPACITY) / workerCount
        let queue = DispatchQueue(label: "memory-allocation-window-stress", attributes: .concurrent)
        var overlappingCloses = 0
        for _ in 0..<4 {
            let ready = DispatchGroup()
            let finished = DispatchGroup()
            let start = DispatchSemaphore(value: 0)
            let counts = AllocationWindowStressCounts()
            for worker in 0..<workerCount {
                ready.enter()
                finished.enter()
                queue.async {
                    ready.leave()
                    start.wait()
                    var failures = 0
                    for _ in 0..<cyclesPerWorker {
                        var entry = dd_memory_live_sample_t()
                        entry.address = UnsafeRawPointer(bitPattern: 0x10000 + worker * 16)
                        entry.size = UInt64(worker + 1)
                        entry.weight = 1
                        if dd_memory_allocation_window_record(
                            handle.window, handle.generation, &entry
                        ) != DD_MEMORY_LIVE_SET_INSERTED {
                            failures += 1
                        }
                        if !dd_memory_allocation_window_remove(handle.window, handle.generation, entry.address) {
                            failures += 1
                        }
                    }
                    counts.record(failures: failures)
                    finished.leave()
                }
            }
            XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
            for _ in 0..<workerCount {
                start.signal()
            }

            // Only the owner closes windows; producers and removers remain ungated after startup.
            var allocObjects = 0.0
            var allocSpace = 0.0
            var recorded = UInt64(0)
            var dropped = UInt64(0)
            for _ in 0..<32 {
                if finished.wait(timeout: .now()) == .timedOut {
                    overlappingCloses += 1
                }
                for aggregate in closeWindow() {
                    allocObjects += aggregate.alloc_objects
                    allocSpace += aggregate.alloc_space
                }
                let diagnostics = dd_memory_allocation_window_closed_diagnostics(window)
                recorded += diagnostics.recorded_allocations
                dropped += diagnostics.dropped_alloc_records
            }
            let completion = finished.wait(timeout: .now() + 60)
            XCTAssertEqual(completion, .success)
            if completion != .success {
                finished.wait()
            }
            let finalWindow = closeWindow()
            for aggregate in finalWindow {
                allocObjects += aggregate.alloc_objects
                allocSpace += aggregate.alloc_space
            }
            let finalDiagnostics = dd_memory_allocation_window_closed_diagnostics(window)
            recorded += finalDiagnostics.recorded_allocations
            dropped += finalDiagnostics.dropped_alloc_records
            XCTAssertEqual(counts.snapshot(), 0)
            XCTAssertEqual(allocObjects, Double(workerCount * cyclesPerWorker))
            XCTAssertEqual(allocSpace, Double(cyclesPerWorker * workerCount * (workerCount + 1) / 2))
            XCTAssertEqual(recorded, UInt64(workerCount * cyclesPerWorker))
            XCTAssertEqual(dropped, 0)
            XCTAssertEqual(finalWindow.reduce(0) { $0 + $1.inuse_objects }, 0)
            XCTAssertEqual(finalDiagnostics.live_set.occupancy, 0)
            XCTAssertEqual(finalDiagnostics.live_set.dropped_samples, 0)
        }
        XCTAssertGreaterThan(overlappingCloses, 0)
    }

    func testConcurrentRecordingAndRemovalRemainSafeAcrossStopAndRestart() throws {
        let handle = AllocationWindowHandle(window: try XCTUnwrap(window), generation: generation)
        let workerCount = 8
        let ready = DispatchGroup()
        let producing = DispatchGroup()
        let finished = DispatchGroup()
        let start = DispatchSemaphore(value: 0)
        let counts = AllocationWindowStressCounts()
        let queue = DispatchQueue(label: "memory-allocation-window-lifecycle-stress", attributes: .concurrent)
        // Drain producers before tearDown can destroy their window, including on timeout.
        defer { finished.wait() }
        for worker in 0..<workerCount {
            ready.enter()
            producing.enter()
            finished.enter()
            queue.async {
                ready.leave()
                start.wait()
                var failures = 0
                for cycle in 0..<10_000 {
                    var entry = dd_memory_live_sample_t()
                    entry.address = UnsafeRawPointer(bitPattern: 0x10000 + worker * 16)
                    entry.size = UInt64(worker + 1)
                    entry.weight = 1
                    let token = dd_memory_allocation_window_diagnostics(handle.window).live_set.generation
                    switch dd_memory_allocation_window_record(handle.window, token, &entry) {
                    case DD_MEMORY_LIVE_SET_INSERTED:
                        // A restart may clear this entry before its removal.
                        _ = dd_memory_allocation_window_remove(handle.window, token, entry.address)
                    case DD_MEMORY_LIVE_SET_STALE_GENERATION:
                        break
                    default:
                        failures += 1
                    }
                    if cycle == 0 {
                        producing.leave()
                    }
                }
                counts.record(failures: failures)
                finished.leave()
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
        for _ in 0..<workerCount {
            start.signal()
        }
        XCTAssertEqual(producing.wait(timeout: .now() + 10), .success)

        // Only the owner changes lifecycle; workers remain ungated after startup.
        var overlappingRestarts = 0
        for _ in 0..<20 {
            if finished.wait(timeout: .now()) == .timedOut {
                overlappingRestarts += 1
            }
            _ = closeWindow()
            dd_memory_allocation_window_stop(window)
            generation = dd_memory_allocation_window_start(window)
            XCTAssertNotEqual(generation, 0)
        }
        let completion = finished.wait(timeout: .now() + 60)
        XCTAssertEqual(completion, .success)
        guard completion == .success else {
            return
        }
        XCTAssertGreaterThan(overlappingRestarts, 0)
        XCTAssertEqual(counts.snapshot(), 0)
        XCTAssertEqual(dd_memory_allocation_window_diagnostics(window).live_set.occupancy, 0)

        XCTAssertEqual(record(sample(at: 0x90000, size: 9)), DD_MEMORY_LIVE_SET_INSERTED)
        let oldGeneration = generation
        dd_memory_allocation_window_stop(window)
        generation = dd_memory_allocation_window_start(window)
        XCTAssertNotEqual(generation, oldGeneration)
        let diagnostics = dd_memory_allocation_window_diagnostics(window)
        XCTAssertEqual(diagnostics.recorded_allocations, 0)
        XCTAssertEqual(diagnostics.dropped_alloc_records, 0)
        XCTAssertEqual(diagnostics.live_set.occupancy, 0)
        var staleEntry = sample(at: 0x90010, size: 100)
        XCTAssertEqual(
            dd_memory_allocation_window_record(window, oldGeneration, &staleEntry),
            DD_MEMORY_LIVE_SET_STALE_GENERATION
        )
        XCTAssertFalse(dd_memory_allocation_window_remove(window, oldGeneration, staleEntry.address))
        XCTAssertTrue(closeWindow().isEmpty)

        XCTAssertEqual(record(sample(at: 0xa0000, size: 7, weight: 1.5)), DD_MEMORY_LIVE_SET_INSERTED)
        assertTotals(closeWindow(), allocObjects: 1.5, allocSpace: 10.5, inuseObjects: 1.5, inuseSpace: 10.5)
        XCTAssertTrue(remove(0xa0000))
        XCTAssertTrue(closeWindow().isEmpty)
    }

    private func sample(at address: UInt, size: UInt64, weight: Double = 1) -> dd_memory_live_sample_t {
        var entry = dd_memory_live_sample_t()
        entry.address = UnsafeRawPointer(bitPattern: address)
        entry.size = size
        entry.weight = weight
        return entry
    }

    private func record(_ sample: dd_memory_live_sample_t) -> dd_memory_live_insert_result_t {
        var entry = sample
        return dd_memory_allocation_window_record(window, generation, &entry)
    }

    private func remove(_ address: UInt) -> Bool {
        dd_memory_allocation_window_remove(window, generation, UnsafeRawPointer(bitPattern: address))
    }

    // Aggregate copies borrow class-name bytes until the next close or start.
    private func closeWindow() -> [dd_memory_aggregate_t] {
        XCTAssertTrue(dd_memory_allocation_window_close(window, generation))
        let view = dd_memory_allocation_window_view(window)
        return Array(UnsafeBufferPointer(start: view.samples, count: view.count))
    }

    private func assertTotals(
        _ aggregates: [dd_memory_aggregate_t],
        allocObjects: Double,
        allocSpace: Double,
        inuseObjects: Double,
        inuseSpace: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(aggregates.reduce(0) { $0 + $1.alloc_objects }, allocObjects, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(aggregates.reduce(0) { $0 + $1.alloc_space }, allocSpace, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(aggregates.reduce(0) { $0 + $1.inuse_objects }, inuseObjects, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(aggregates.reduce(0) { $0 + $1.inuse_space }, inuseSpace, accuracy: 1e-6, file: file, line: line)
    }

    private func collidingAddresses(count: Int) -> [UInt] {
        let first = UInt(0x10_0000)
        let bucket = dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: first))
        var addresses: [UInt] = []
        for index in 0..<1_000_000 {
            let address = first + UInt(index) * 16
            if dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: address)) == bucket {
                addresses.append(address)
                if addresses.count == count {
                    return addresses
                }
            }
        }
        XCTFail("Could not construct enough colliding addresses")
        return addresses
    }
}

private struct AllocationWindowHandle: @unchecked Sendable {
    let window: OpaquePointer
    let generation: UInt64
}

private final class AllocationWindowStressCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = 0

    func record(failures: Int) {
        lock.lock()
        self.failures += failures
        lock.unlock()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }
}

private func resolveAllocationWindowSwiftName(_ metadata: OpaquePointer?) -> dd_swift_class_name_t {
    if let metadata {
        UnsafeMutableRawPointer(metadata).assumingMemoryBound(to: Int.self).pointee += 1
    }
    return dd_swift_class_name_t()
}

#endif // !os(watchOS)
