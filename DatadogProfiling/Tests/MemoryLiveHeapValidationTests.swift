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
        ObjCAllocInterception.stop()
        dd_memory_test_reset()
        warmUpFixtureClasses()
    }

    override func tearDown() {
        ObjCAllocInterception.stop()
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

        let sampledFreesBeforeRelease = MemoryProfilerProbe.diagnostics().sampledFrees
        object = nil
        XCTAssertNil(weakObject.value, "The fixture must be deallocated before validating the live set")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), 0)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerProbe.diagnostics().sampledFrees - sampledFreesBeforeRelease,
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

        let sampledFreesBeforeReleasingGroupB = MemoryProfilerProbe.diagnostics().sampledFrees
        let releasedGroupBObject = WeakReference(groupB?.first)
        groupB = nil
        XCTAssertNil(releasedGroupBObject.value, "Group B must be released before the first live-set assertion")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), objectCount)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerProbe.diagnostics().sampledFrees - sampledFreesBeforeReleasingGroupB,
            UInt64(objectCount)
        )

        let sampledFreesBeforeReleasingGroupC = MemoryProfilerProbe.diagnostics().sampledFrees
        let releasedGroupCObject = WeakReference(groupC?.first)
        groupC = nil
        XCTAssertNil(releasedGroupCObject.value, "Group C must be released before the second live-set assertion")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), objectCount)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), 0)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerProbe.diagnostics().sampledFrees - sampledFreesBeforeReleasingGroupC,
            UInt64(objectCount)
        )

        let sampledFreesBeforeReleasingGroupA = MemoryProfilerProbe.diagnostics().sampledFrees
        let releasedGroupAObject = WeakReference(groupA?.first)
        groupA = nil
        XCTAssertNil(releasedGroupAObject.value, "Group A must be released before the final live-set assertion")

        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupA.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupB.self), 0)
        XCTAssertEqual(liveCount(for: MemoryLiveHeapValidationGroupC.self), 0)
        XCTAssertGreaterThanOrEqual(
            MemoryProfilerProbe.diagnostics().sampledFrees - sampledFreesBeforeReleasingGroupA,
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
        XCTAssertEqual(Set(MemoryProfilerProbe.captureSnapshot().samples.map(\.address)), Set(addresses))

        observeDeallocation(at: addresses[0])
        XCTAssertEqual(
            Set(MemoryProfilerProbe.captureSnapshot().samples.map(\.address)),
            Set(addresses.dropFirst())
        )

        // The third key sits beyond the first key's tombstone. A lookup that
        // mistakes the tombstone for an empty slot will fail this removal.
        observeDeallocation(at: addresses[2])
        XCTAssertEqual(
            Set(MemoryProfilerProbe.captureSnapshot().samples.map(\.address)),
            [addresses[1]]
        )
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().sampledFrees, 2)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().droppedSamples, 0)

        observeDeallocation(at: addresses[1])
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().liveSampledAllocations, 0)
    }

    /// Insert and remove probe at most `MAX_PROBE_DISTANCE` slots, so a key whose
    /// probe window is full is dropped even while free slots remain elsewhere in
    /// the table. The table therefore saturates a little below its slot count.
    ///
    /// That is the deliberate trade for a bounded free: `remove_sample` runs on
    /// every deallocation in the process, and an unbounded probe would decay
    /// towards a full-table scan as empty slots are consumed. Dropping a sample
    /// censors `inuse_*`, which the design permits; a scan on every free does not.
    func testTableSaturatesWithinProbeBoundAndCountsDrops() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        let generation = dd_memory_test_session_generation()
        let slotCount = 4_096
        let addresses = (0..<slotCount).map { UInt64(0x10_0000 + $0 * 0x10) }

        var admitted: [UInt64] = []
        var rejected: [UInt64] = []
        for (index, address) in addresses.enumerated() {
            if insertTableSample(at: address, size: UInt64(index + 1), generation: generation) {
                admitted.append(address)
            } else {
                rejected.append(address)
            }
        }

        XCTAssertFalse(admitted.isEmpty, "The table must admit samples")
        XCTAssertFalse(
            rejected.isEmpty,
            "Probing is bounded, so a full slot window must reject before every slot is used"
        )
        XCTAssertGreaterThan(
            admitted.count, slotCount * 3 / 4,
            "The probe bound must not cost more than a small fraction of usable capacity"
        )

        // Drop-new, never evict: every admitted sample is still live and unique,
        // and every rejection is counted.
        let diagnostics = MemoryProfilerProbe.diagnostics()
        XCTAssertEqual(diagnostics.liveSampledAllocations, UInt64(admitted.count))
        XCTAssertEqual(diagnostics.droppedSamples, UInt64(rejected.count))

        let snapshot = MemoryProfilerProbe.captureSnapshot()
        XCTAssertEqual(snapshot.samples.count, admitted.count)
        XCTAssertEqual(Set(snapshot.samples.map(\.address)), Set(admitted))
    }

    /// A removal leaves a tombstone; a later insert whose probe reaches that slot
    /// must reuse it rather than reporting the table full.
    func testInsertReusesTombstoneWithinProbeWindow() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        let generation = dd_memory_test_session_generation()
        // All four keys must come from the SAME call: `findCollidingAddresses`
        // returns whichever bucket first reaches the requested count, so asking
        // twice can yield two different buckets.
        let colliding = findCollidingAddresses(count: 4)
        guard colliding.count == 4 else {
            return XCTFail("The fixture must find four addresses in the same table bucket")
        }
        XCTAssertEqual(Set(colliding.map(tableBucket)).count, 1, "All four keys must share a bucket")

        let addresses = Array(colliding.prefix(3))
        let reuseAddress = colliding[3]

        for (index, address) in addresses.enumerated() {
            XCTAssertTrue(insertTableSample(at: address, size: UInt64(index + 1), generation: generation))
        }
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().liveSampledAllocations, 3)

        // Free the head of the chain, leaving a tombstone in the shared bucket.
        observeDeallocation(at: addresses[0])
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().liveSampledAllocations, 2)

        // The fourth key probes the same bucket and must reuse the tombstone.
        XCTAssertTrue(insertTableSample(at: reuseAddress, size: 99, generation: generation))

        let snapshot = MemoryProfilerProbe.captureSnapshot()
        XCTAssertEqual(snapshot.samples.count, 3)
        XCTAssertFalse(snapshot.samples.contains { $0.address == addresses[0] })
        XCTAssertEqual(snapshot.samples.first { $0.address == reuseAddress }?.size, 99)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().droppedSamples, 0)
    }

    func testRestartClearsSamplesFromPreviousSession() {
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        observeForcedAllocation(at: 0x2_0000, size: 64)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().liveSampledAllocations, 1)

        dd_memory_profiler_stop()
        XCTAssertTrue(dd_memory_profiler_start_passive(1))

        XCTAssertEqual(MemoryProfilerProbe.diagnostics().liveSampledAllocations, 0)
        XCTAssertTrue(MemoryProfilerProbe.captureSnapshot().samples.isEmpty)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().sampledAllocations, 0)
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
        XCTAssertTrue(MemoryProfilerProbe.captureSnapshot().samples.isEmpty)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().sampledAllocations, 0)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().droppedSamples, 0)
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
            let snapshot = MemoryProfilerProbe.captureSnapshot()
            XCTAssertEqual(Set(snapshot.samples.map(\.address)).count, snapshot.samples.count)
            for sample in snapshot.samples {
                XCTAssertEqual(sample.size, expectedSizes[sample.address])
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().liveSampledAllocations, 0)
        XCTAssertEqual(MemoryProfilerProbe.diagnostics().droppedSamples, 0)
    }

    private func startMemoryProfiler() {
        let status = ObjCAllocInterception.start(poissonRateBytes: 1)
        XCTAssertEqual(status, .ok, "The allocation swizzle must install in a clean test process")
        XCTAssertTrue(ObjCAllocInterception.isRunning)
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
        return MemoryProfilerProbe.captureSnapshot().samples.reduce(into: 0) { count, sample in
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
