/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import Foundation
import XCTest
import DatadogMachProfiler
import DatadogMachProfiler.Testing
@testable import DatadogProfiling

@objc(DDMemoryLiveHeapValidationGroupA)
private final class MemoryLiveHeapValidationGroupA: NSObject {}

@objc(DDMemoryLiveHeapValidationGroupB)
private final class MemoryLiveHeapValidationGroupB: NSObject {}

@objc(DDMemoryLiveHeapValidationGroupC)
private final class MemoryLiveHeapValidationGroupC: NSObject {}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

/// Deterministic lifecycle validation for sampled Objective-C allocations.
///
/// Forced sampling makes the expected fixture-class live-set counts exact. Weak references prove
/// ARC has deallocated each fixture before the test verifies that the `-dealloc` bridge removed
/// the corresponding sample.
final class MemoryLiveHeapValidationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MemorySwizzlingPOC.stop()
        dd_memory_test_reset()
        warmUpFixtureClasses()
    }

    override func tearDown() {
        MemorySwizzlingPOC.stop()
        dd_memory_test_reset()
        super.tearDown()
    }

    func testRetainedSamplesRemainLiveAcrossSnapshots() {
        startMemoryProfiler()

        let objectCount = 16
        let objects = allocate(objectCount) { MemoryLiveHeapValidationGroupA() }

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)

        withExtendedLifetime(objects) {}
    }

    func testReleasedSampleIsRemovedFromLiveSet() {
        startMemoryProfiler()

        var object: MemoryLiveHeapValidationGroupA? = allocateOne {
            MemoryLiveHeapValidationGroupA()
        }
        let weakObject = WeakReference(object)

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), 1)

        let sampledFreesBeforeRelease = MemoryProfilerPOC.diagnostics().sampledFrees
        object = nil
        XCTAssertNil(weakObject.value, "The fixture must be deallocated before validating the live set")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), 0)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerPOC.diagnostics().sampledFrees - sampledFreesBeforeRelease,
            1
        )
    }

    func testThreePhaseLifecycleTracksOnlyRetainedGroups() {
        startMemoryProfiler()

        let objectCount = 8
        var groupA: [MemoryLiveHeapValidationGroupA]? = allocate(objectCount) {
            MemoryLiveHeapValidationGroupA()
        }
        var groupB: [MemoryLiveHeapValidationGroupB]? = allocate(objectCount) {
            MemoryLiveHeapValidationGroupB()
        }
        var groupC: [MemoryLiveHeapValidationGroupC]? = allocate(objectCount) {
            MemoryLiveHeapValidationGroupC()
        }

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), objectCount)

        let sampledFreesBeforeReleasingGroupB = MemoryProfilerPOC.diagnostics().sampledFrees
        let releasedGroupBObject = WeakReference(groupB?.first)
        groupB = nil
        XCTAssertNil(releasedGroupBObject.value, "Group B must be released before the first live-set assertion")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), objectCount)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerPOC.diagnostics().sampledFrees - sampledFreesBeforeReleasingGroupB,
            UInt64(objectCount)
        )

        let sampledFreesBeforeReleasingGroupC = MemoryProfilerPOC.diagnostics().sampledFrees
        let releasedGroupCObject = WeakReference(groupC?.first)
        groupC = nil
        XCTAssertNil(releasedGroupCObject.value, "Group C must be released before the second live-set assertion")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), 0)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerPOC.diagnostics().sampledFrees - sampledFreesBeforeReleasingGroupC,
            UInt64(objectCount)
        )

        let sampledFreesBeforeReleasingGroupA = MemoryProfilerPOC.diagnostics().sampledFrees
        let releasedGroupAObject = WeakReference(groupA?.first)
        groupA = nil
        XCTAssertNil(releasedGroupAObject.value, "Group A must be released before the final live-set assertion")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), 0)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerPOC.diagnostics().sampledFrees - sampledFreesBeforeReleasingGroupA,
            UInt64(objectCount)
        )
    }

    func testCollidingSamplesRemainRemovablePastTombstones() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        let addresses = findCollidingAddresses(count: 3)
        guard addresses.count == 3 else {
            return XCTFail("The fixture must find three addresses in the same table bucket")
        }
        XCTAssertEqual(Set(addresses.map(tableBucket)), [tableBucket(for: addresses[0])])

        for (index, address) in addresses.enumerated() {
            observeForcedAllocation(at: address, size: UInt64(index + 1))
        }
        XCTAssertEqual(Set(MemoryProfilerPOC.captureSnapshot().samples.map(\.address)), Set(addresses))

        observeDeallocation(at: addresses[0])
        XCTAssertEqual(
            Set(MemoryProfilerPOC.captureSnapshot().samples.map(\.address)),
            Set(addresses.dropFirst())
        )

        // The third key sits beyond the first key's tombstone. A lookup that
        // mistakes the tombstone for an empty slot will fail this removal.
        observeDeallocation(at: addresses[2])
        XCTAssertEqual(
            Set(MemoryProfilerPOC.captureSnapshot().samples.map(\.address)),
            [addresses[1]]
        )
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().sampledFrees, 2)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().droppedSamples, 0)

        observeDeallocation(at: addresses[1])
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().liveSampledAllocations, 0)
    }

    func testFullTableRejectsOverflowAndReusesTombstone() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        let generation = dd_memory_test_session_generation()
        let capacity = 4_096
        let addresses = (0..<capacity).map { UInt64(0x10_0000 + $0 * 0x10) }

        for (index, address) in addresses.enumerated() {
            XCTAssertTrue(
                insertTableSample(at: address, size: UInt64(index + 1), generation: generation),
                "Insertion \(index) must fit within the declared table capacity"
            )
        }

        let overflowAddress = UInt64(0x20_0000)
        XCTAssertFalse(insertTableSample(at: overflowAddress, size: 1, generation: generation))
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().liveSampledAllocations, UInt64(capacity))
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().droppedSamples, 1)

        observeDeallocation(at: addresses[capacity / 2])
        XCTAssertTrue(insertTableSample(at: overflowAddress, size: 99, generation: generation))

        let snapshot = MemoryProfilerPOC.captureSnapshot()
        XCTAssertEqual(snapshot.samples.count, capacity)
        XCTAssertEqual(Set(snapshot.samples.map(\.address)).count, capacity)
        XCTAssertFalse(snapshot.samples.contains { $0.address == addresses[capacity / 2] })
        XCTAssertEqual(snapshot.samples.first { $0.address == overflowAddress }?.size, 99)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().droppedSamples, 1)
    }

    func testRestartClearsSamplesFromPreviousSession() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        observeForcedAllocation(at: 0x2_0000, size: 64)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().liveSampledAllocations, 1)

        dd_memory_profiler_stop()
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        XCTAssertEqual(MemoryProfilerPOC.diagnostics().liveSampledAllocations, 0)
        XCTAssertTrue(MemoryProfilerPOC.captureSnapshot().samples.isEmpty)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().sampledAllocations, 0)
    }

    func testWorkFromPreviousSessionCannotEnterRestartedTable() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))
        let previousGeneration = dd_memory_test_session_generation()

        dd_memory_profiler_stop()
        XCTAssertTrue(dd_memory_profiler_start_passive(1))
        XCTAssertNotEqual(dd_memory_test_session_generation(), previousGeneration)

        XCTAssertFalse(
            insertTableSample(at: 0x2_1000, size: 64, generation: previousGeneration),
            "An insertion carrying a stale session token must be rejected"
        )
        XCTAssertTrue(MemoryProfilerPOC.captureSnapshot().samples.isEmpty)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().sampledAllocations, 0)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().droppedSamples, 0)
    }

    func testSnapshotsRemainConsistentDuringConcurrentSlotReuse() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        var expectedSizes: [UInt64: UInt64] = [:]
        for index in 0..<8 {
            let address = UInt64(0x3_0000) + UInt64(index) * UInt64(0x1_0000)
            expectedSizes[address] = UInt64(index + 1)
        }
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "memory-table-churn", attributes: .concurrent)

        for (address, size) in expectedSizes {
            group.enter()
            queue.async {
                for _ in 0..<250 {
                    self.observeForcedAllocation(at: address, size: size)
                    self.observeDeallocation(at: address)
                }
                group.leave()
            }
        }

        for _ in 0..<100 {
            let snapshot = MemoryProfilerPOC.captureSnapshot()
            XCTAssertEqual(Set(snapshot.samples.map(\.address)).count, snapshot.samples.count)
            for sample in snapshot.samples {
                XCTAssertEqual(sample.size, expectedSizes[sample.address])
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().liveSampledAllocations, 0)
        XCTAssertEqual(MemoryProfilerPOC.diagnostics().droppedSamples, 0)
    }

    private func startMemoryProfiler() {
        let status = MemorySwizzlingPOC.start(poissonRateBytes: 1)
        XCTAssertEqual(status, .ok, "The allocation swizzle must install in a clean test process")
        XCTAssertTrue(MemorySwizzlingPOC.isRunning)
    }

    private func warmUpFixtureClasses() {
        // Resolve Swift/Objective-C class metadata before installing the process-wide swizzle.
        // Otherwise the first forced allocation can become visible one snapshot late while
        // the runtime performs one-time class initialization.
        _ = NSStringFromClass(MemoryLiveHeapValidationGroupA.self)
        _ = NSStringFromClass(MemoryLiveHeapValidationGroupB.self)
        _ = NSStringFromClass(MemoryLiveHeapValidationGroupC.self)
    }

    private func allocate<Object: NSObject>(
        _ count: Int,
        makeObject: () -> Object
    ) -> [Object] {
        var objects: [Object] = []
        objects.reserveCapacity(count)

        for _ in 0..<count {
            objects.append(allocateOne(makeObject: makeObject))
        }
        return objects
    }

    private func allocateOne<Object: NSObject>(
        makeObject: () -> Object
    ) -> Object {
        dd_memory_test_force_next_sample()
        return makeObject()
    }

    private func liveCount<Object: NSObject>(for type: Object.Type) -> Int {
        let expectedClassName = NSStringFromClass(type)
        return MemoryProfilerPOC.captureSnapshot().samples.reduce(into: 0) { count, sample in
            if sample.className == expectedClassName {
                count += 1
            }
        }
    }

    private func observeForcedAllocation(at address: UInt64, size: UInt64) {
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else {
            return XCTFail("The synthetic address must produce a non-null pointer")
        }
        dd_memory_test_force_next_sample()
        dd_memory_observe_allocation(pointer, size, nil)
    }

    private func observeDeallocation(at address: UInt64) {
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else {
            return XCTFail("The synthetic address must produce a non-null pointer")
        }
        dd_memory_observe_deallocation(pointer)
    }

    private func insertTableSample(
        at address: UInt64,
        size: UInt64,
        generation: UInt64
    ) -> Bool {
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else {
            XCTFail("The synthetic address must produce a non-null pointer")
            return false
        }
        return dd_memory_test_insert_sample(pointer, size, generation)
    }

    private func tableBucket(for address: UInt64) -> UInt64 {
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else {
            return .max
        }
        return UInt64(dd_memory_test_bucket_for(pointer))
    }

    private func findCollidingAddresses(count: Int) -> [UInt64] {
        var addressesByBucket: [UInt64: [UInt64]] = [:]
        for index in 0..<100_000 {
            let address = UInt64(0x1_0000 + index * 0x10)
            let bucket = tableBucket(for: address)
            addressesByBucket[bucket, default: []].append(address)
            if addressesByBucket[bucket]?.count == count {
                return addressesByBucket[bucket] ?? []
            }
        }
        return []
    }
}

#endif // !os(watchOS)
