/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest
import DatadogMachProfiler.Testing

final class MemoryLiveSetTests: XCTestCase {
    private var table: OpaquePointer?
    private var snapshotStorage: OpaquePointer?
    private var generation: UInt64 = 0

    override func setUp() {
        super.setUp()
        table = dd_memory_live_set_create()
        XCTAssertNotNil(table)
        snapshotStorage = dd_memory_live_snapshot_create()
        XCTAssertNotNil(snapshotStorage)
        generation = dd_memory_live_set_start(table)
        XCTAssertNotEqual(generation, 0)
    }

    override func tearDown() {
        dd_memory_live_set_stop(table)
        dd_memory_live_set_destroy(table)
        dd_memory_live_snapshot_destroy(snapshotStorage)
        table = nil
        snapshotStorage = nil
        super.tearDown()
    }

    func testCollisionBoundDropsNewAndReusesTombstone() {
        let addresses = collidingAddresses(count: Int(DD_MEMORY_LIVE_SET_MAX_PROBE) + 1)
        XCTAssertEqual(addresses.count, Int(DD_MEMORY_LIVE_SET_MAX_PROBE) + 1)

        for (index, address) in addresses.dropLast().enumerated() {
            XCTAssertEqual(insert(address, size: UInt64(index + 1)), DD_MEMORY_LIVE_SET_INSERTED)
        }
        let admitted = Set(addresses.dropLast())
        let rejected = addresses.last!
        XCTAssertEqual(insert(rejected, size: 999), DD_MEMORY_LIVE_SET_DROPPED)
        XCTAssertEqual(Set(snapshot().map { UInt(bitPattern: $0.address) }), admitted)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).dropped_samples, 1)

        XCTAssertTrue(remove(addresses[0]))
        XCTAssertTrue(remove(addresses[30]))
        XCTAssertEqual(insert(rejected, size: 999), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertTrue(remove(rejected))
        XCTAssertFalse(remove(rejected))

        let result = snapshot()
        XCTAssertEqual(result.count, Int(DD_MEMORY_LIVE_SET_MAX_PROBE) - 2)
        let expected = admitted.subtracting([addresses[0], addresses[30]])
        XCTAssertEqual(Set(result.map { UInt(bitPattern: $0.address) }), expected)
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.peak_occupancy, UInt64(DD_MEMORY_LIVE_SET_MAX_PROBE))
        XCTAssertEqual(diagnostics.max_probe_length, UInt64(DD_MEMORY_LIVE_SET_MAX_PROBE))
        XCTAssertEqual(diagnostics.tombstones, 2)
        XCTAssertTrue(diagnostics.reached_admission_limit)
        XCTAssertGreaterThan(diagnostics.total_probe_length, 0)
        XCTAssertLessThanOrEqual(diagnostics.max_probe_length, UInt64(DD_MEMORY_LIVE_SET_MAX_PROBE))
    }

    func testCollidingSamplesRemainRemovableAcrossTableWraparound() {
        let probeLimit = Int(DD_MEMORY_LIVE_SET_MAX_PROBE)
        let bucket = Int(DD_MEMORY_LIVE_SET_CAPACITY) - 3
        let addresses = collidingAddresses(count: probeLimit, bucket: bucket)
        guard addresses.count == probeLimit else {
            XCTFail("Could not construct enough colliding addresses")
            return
        }
        for address in addresses {
            XCTAssertEqual(insert(address, size: UInt64(address)), DD_MEMORY_LIVE_SET_INSERTED)
        }

        for address in addresses.dropLast() {
            XCTAssertTrue(remove(address))
            XCTAssertFalse(remove(address))
        }
        let survivor = addresses.last!
        XCTAssertEqual(snapshot().map { UInt(bitPattern: $0.address) }, [survivor])
        XCTAssertTrue(remove(survivor))
        XCTAssertTrue(snapshot().isEmpty)
    }

    func testDuplicateAndDroppedSamplesDoNotKeepBucketNonempty() {
        let probeLimit = Int(DD_MEMORY_LIVE_SET_MAX_PROBE)
        let addresses = collidingAddresses(count: probeLimit + 1)
        guard addresses.count == probeLimit + 1 else {
            XCTFail("Could not construct enough colliding addresses")
            return
        }
        for address in addresses.dropLast() {
            XCTAssertEqual(insert(address, size: UInt64(address)), DD_MEMORY_LIVE_SET_INSERTED)
        }
        XCTAssertEqual(insert(addresses[0], size: 999), DD_MEMORY_LIVE_SET_DUPLICATE)
        let rejected = addresses.last!
        XCTAssertEqual(insert(rejected, size: 999), DD_MEMORY_LIVE_SET_DROPPED)
        for address in addresses.dropLast() { XCTAssertTrue(remove(address)) }

        var probeLength = 99
        XCTAssertFalse(dd_memory_live_set_remove_with_probe_length_for_testing(
            table, generation, UnsafeRawPointer(bitPattern: rejected), &probeLength
        ))
        XCTAssertEqual(probeLength, 0)
        XCTAssertTrue(snapshot().isEmpty)
    }

    func testSnapshotDiagnosticsRemainAtTheCaptureBoundary() {
        let storageBytes = dd_memory_live_snapshot_storage_bytes(snapshotStorage)
        XCTAssertGreaterThan(storageBytes, 0)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).occupancy, 0)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).snapshot_bytes_high_water, 0)
        XCTAssertEqual(insert(0x10000, size: 16), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(snapshot().count, 1)
        XCTAssertEqual(dd_memory_live_snapshot_storage_bytes(snapshotStorage), storageBytes)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).snapshot_bytes_high_water, storageBytes)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).snapshot_bytes_high_water, storageBytes)
        XCTAssertTrue(remove(0x10000))
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).occupancy, 0)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).occupancy, 1)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).generation, generation)

        XCTAssertFalse(dd_memory_live_set_snapshot(table, generation + 1, snapshotStorage))
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).generation, 0)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).occupancy, 0)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(snapshotStorage).snapshot_bytes_high_water, 0)
        XCTAssertEqual(dd_memory_live_snapshot_storage_bytes(snapshotStorage), storageBytes)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).snapshot_bytes_high_water, storageBytes)
        XCTAssertEqual(dd_memory_live_snapshot_storage_bytes(nil), 0)
        XCTAssertEqual(dd_memory_live_snapshot_diagnostics(nil).occupancy, 0)
    }

    func testRestartRejectsStaleWorkAndClearsSamples() {
        XCTAssertEqual(insert(0x10000, size: 42), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(snapshot().map(\.size), [42])
        let oldGeneration = generation
        dd_memory_live_set_stop(table)
        XCTAssertFalse(dd_memory_live_set_snapshot(table, oldGeneration, snapshotStorage))
        XCTAssertEqual(dd_memory_live_snapshot_view(snapshotStorage).count, 0)
        let stoppedDiagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertFalse(stoppedDiagnostics.is_active)
        XCTAssertEqual(stoppedDiagnostics.occupancy, 1)
        generation = dd_memory_live_set_start(table)
        XCTAssertNotEqual(generation, oldGeneration)
        XCTAssertTrue(snapshot().isEmpty)

        var staleSample = sample(at: 0x20000, size: 64)
        let staleResult = dd_memory_live_set_insert(table, oldGeneration, &staleSample)
        XCTAssertEqual(staleResult, DD_MEMORY_LIVE_SET_STALE_GENERATION)
        let staleAddress = UnsafeRawPointer(bitPattern: 0x10000)
        XCTAssertFalse(dd_memory_live_set_remove(table, oldGeneration, staleAddress))
        var probeLength = 99
        XCTAssertFalse(dd_memory_live_set_remove_with_probe_length_for_testing(
            table, generation, staleAddress, &probeLength
        ))
        XCTAssertEqual(probeLength, 0)
        XCTAssertTrue(snapshot().isEmpty)
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.stale_generation_rejections, 2)
        XCTAssertEqual(diagnostics.dropped_samples, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.generation_transitions, 3)
    }

    func testMissProbeLengthIsBoundedAfterEverySlotBecomesATombstone() {
        let missingAddress = UnsafeRawPointer(bitPattern: 0x2000_0000)
        var probeLength = 99
        XCTAssertFalse(dd_memory_live_set_remove_with_probe_length_for_testing(
            table, generation, missingAddress, &probeLength
        ))
        XCTAssertEqual(probeLength, 0)

        let addresses = fillTableWithOneEntryPerBucket()
        guard addresses.count == Int(DD_MEMORY_LIVE_SET_CAPACITY) else {
            return
        }
        let insertionProbeCount = dd_memory_live_set_diagnostics(table).probe_count
        XCTAssertFalse(dd_memory_live_set_remove_with_probe_length_for_testing(
            table, generation, missingAddress, &probeLength
        ))
        XCTAssertEqual(probeLength, Int(DD_MEMORY_LIVE_SET_MAX_PROBE))

        for address in addresses { XCTAssertTrue(remove(address)) }
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).tombstones, UInt64(addresses.count))
        XCTAssertFalse(dd_memory_live_set_remove_with_probe_length_for_testing(
            table, generation, missingAddress, &probeLength
        ))
        XCTAssertEqual(probeLength, 0)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).probe_count, insertionProbeCount)

        generation = dd_memory_live_set_start(table)
        XCTAssertFalse(dd_memory_live_set_remove_with_probe_length_for_testing(
            table, generation, missingAddress, &probeLength
        ))
        XCTAssertEqual(probeLength, 0)
    }

    func testInvalidSnapshotsClearResultsAndRejectInconsistentOccupancy() {
        XCTAssertEqual(insert(0x10000, size: 1), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(insert(0x20000, size: 2), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(Set(snapshot().map(\.size)), [1, 2])
        defer {
            dd_memory_live_set_override_occupancy_for_testing(table, 2)
        }
        let cases: [UInt64] = [0, 1, 3, UInt64(DD_MEMORY_LIVE_SET_CAPACITY) + 1]
        for occupancy in cases {
            dd_memory_live_set_override_occupancy_for_testing(table, occupancy)
            XCTAssertFalse(dd_memory_live_set_snapshot(table, generation, snapshotStorage))
            XCTAssertEqual(dd_memory_live_snapshot_view(snapshotStorage).count, 0)
        }
        XCTAssertFalse(dd_memory_live_set_snapshot(table, generation, nil))
        XCTAssertEqual(dd_memory_live_snapshot_view(nil).count, 0)
        XCTAssertNil(dd_memory_live_snapshot_view(nil).samples)
        dd_memory_live_snapshot_destroy(nil)
        dd_memory_live_set_override_occupancy_for_testing(table, 2)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).snapshot_failures, UInt64(cases.count + 1))
        XCTAssertEqual(Set(snapshot().map { $0.size }), [1, 2])
        let minimumBytes = UInt64(DD_MEMORY_LIVE_SET_CAPACITY) *
            UInt64(MemoryLayout<dd_memory_live_sample_t>.stride + Int(DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES))
        let storageBytes = dd_memory_live_set_diagnostics(table).snapshot_bytes_high_water
        XCTAssertGreaterThanOrEqual(storageBytes, minimumBytes)
        _ = snapshot()
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).snapshot_bytes_high_water, storageBytes)
    }

    func testDuplicatePreservesOriginalSampleAndResetsDiagnostics() {
        XCTAssertEqual(insert(0x10000, size: 42), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(insert(0x10000, size: 99), DD_MEMORY_LIVE_SET_DUPLICATE)
        XCTAssertEqual(snapshot().map(\.size), [42])
        var diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.occupancy, 1)
        XCTAssertEqual(diagnostics.duplicate_samples, 1)
        XCTAssertEqual(diagnostics.dropped_samples, 0)

        generation = dd_memory_live_set_start(table)
        diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.duplicate_samples, 0)
        XCTAssertEqual(diagnostics.occupancy, 0)
    }

    func testSnapshotCapturesLongestStoredNamesAtFullCapacity() {
        let capacity = Int(DD_MEMORY_LIVE_SET_CAPACITY)
        let name = String(repeating: "a", count: Int(DD_MEMORY_LIVE_SET_MAX_CLASS_NAME_BYTES) - 1)
        let addresses = name.withCString { className in
            fillTableWithOneEntryPerBucket { address in
                var entry = Self.taggedSample(at: address)
                entry.class_name = className
                return entry
            }
        }
        guard addresses.count == capacity else {
            return
        }

        let view = captureSnapshot()
        XCTAssertEqual(view.count, capacity)
        let samples = UnsafeBufferPointer(start: view.samples, count: view.count)
        for entry in samples {
            XCTAssertEqual(String(cString: entry.class_name!), name)
        }
        XCTAssertEqual(Set(samples.map { UInt(bitPattern: $0.address) }), Set(addresses))
    }

    func testSnapshotStorageCanBeReusedIndependentlyOfTheTable() throws {
        let otherStorage = try XCTUnwrap(dd_memory_live_snapshot_create())
        defer { dd_memory_live_snapshot_destroy(otherStorage) }
        XCTAssertEqual(dd_memory_live_snapshot_view(snapshotStorage).count, 0)
        "ExampleClass".withCString { className in
            var entry = sample(at: 0x10000, size: 1)
            entry.class_name = className
            XCTAssertEqual(dd_memory_live_set_insert(table, generation, &entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        let firstView = captureSnapshot()
        let firstSamples = try XCTUnwrap(firstView.samples)
        XCTAssertEqual(firstView.count, 1)
        XCTAssertTrue(remove(0x10000))
        "UpdatedClass".withCString { className in
            var entry = sample(at: 0x10000, size: 2)
            entry.class_name = className
            XCTAssertEqual(dd_memory_live_set_insert(table, generation, &entry), DD_MEMORY_LIVE_SET_INSERTED)
        }
        XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, otherStorage))
        let otherView = dd_memory_live_snapshot_view(otherStorage)
        let otherSamples = try XCTUnwrap(otherView.samples)
        XCTAssertEqual(otherView.count, 1)
        XCTAssertEqual(firstSamples.pointee.size, 1)
        XCTAssertEqual(String(cString: try XCTUnwrap(firstSamples.pointee.class_name)), "ExampleClass")

        let reusedView = captureSnapshot()
        XCTAssertEqual(reusedView.samples, firstSamples)
        XCTAssertNotEqual(reusedView.samples, otherSamples)
        generation = dd_memory_live_set_start(table)
        dd_memory_live_set_destroy(table)
        table = nil
        for view in [reusedView, otherView] {
            XCTAssertEqual(view.count, 1)
            let entry = try XCTUnwrap(view.samples).pointee
            XCTAssertEqual(entry.size, 2)
            XCTAssertEqual(String(cString: try XCTUnwrap(entry.class_name)), "UpdatedClass")
        }
        XCTAssertFalse(dd_memory_live_set_snapshot(nil, generation, snapshotStorage))
        XCTAssertEqual(dd_memory_live_snapshot_view(snapshotStorage).count, 0)
        XCTAssertEqual(dd_memory_live_snapshot_view(otherStorage).count, 1)
    }

    func testInvalidInputsDoNotEnterTable() {
        var entry = sample(at: 0x10000, size: 1)
        XCTAssertEqual(
            dd_memory_live_set_insert(nil, generation, &entry),
            DD_MEMORY_LIVE_SET_INVALID_SAMPLE
        )
        XCTAssertEqual(
            dd_memory_live_set_insert(table, generation, nil),
            DD_MEMORY_LIVE_SET_INVALID_SAMPLE
        )
        entry.address = UnsafeRawPointer(bitPattern: 1)
        XCTAssertEqual(
            dd_memory_live_set_insert(table, generation, &entry),
            DD_MEMORY_LIVE_SET_INVALID_SAMPLE
        )
        entry.address = UnsafeRawPointer(bitPattern: 0x10000)
        entry.frame_count = UInt32(DD_MEMORY_LIVE_SET_MAX_FRAMES + 1)
        XCTAssertEqual(
            dd_memory_live_set_insert(table, generation, &entry),
            DD_MEMORY_LIVE_SET_INVALID_SAMPLE
        )
        XCTAssertFalse(dd_memory_live_set_remove(table, generation, nil))
        XCTAssertTrue(snapshot().isEmpty)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).occupancy, 0)
    }

    func testHighOccupancyChurnKeepsBoundedProbesAndAccurateOccupancy() {
        let residentCount = Int(DD_MEMORY_LIVE_SET_CAPACITY) / 2
        var residents: [UInt] = []
        for index in 0..<residentCount {
            let address = UInt(0x10_0000 + index * 16)
            XCTAssertEqual(insert(address, size: 1), DD_MEMORY_LIVE_SET_INSERTED)
            residents.append(address)
        }

        var rejected = 0
        for index in 0..<20_000 {
            let position = index % residentCount
            let oldAddress = residents[position]
            XCTAssertTrue(remove(oldAddress))
            let newAddress = UInt(0x20_0000 + index * 16)
            if insert(newAddress, size: 2) == DD_MEMORY_LIVE_SET_INSERTED {
                residents[position] = newAddress
            } else {
                rejected += 1
                XCTAssertEqual(insert(oldAddress, size: 1), DD_MEMORY_LIVE_SET_INSERTED)
            }
            if index.isMultiple(of: 1_000) {
                XCTAssertFalse(remove(0x999_0000 + UInt(index * 16)))
            }
        }
        XCTAssertEqual(Set(snapshot().map { UInt(bitPattern: $0.address) }), Set(residents))
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.occupancy, UInt64(residentCount))
        XCTAssertGreaterThan(diagnostics.peak_tombstones, 0)
        XCTAssertEqual(diagnostics.dropped_samples, UInt64(rejected))
        XCTAssertLessThanOrEqual(
            diagnostics.max_probe_length,
            UInt64(DD_MEMORY_LIVE_SET_MAX_PROBE)
        )
    }

    func testUsableCapacityIsMeasuredByAdmissionRatherThanSlotCount() {
        var admitted: Set<UInt> = []
        var rejected = 0
        for index in 0..<Int(DD_MEMORY_LIVE_SET_CAPACITY) {
            let address = UInt(0x10_0000 + index * 16)
            switch insert(address, size: 1) {
            case DD_MEMORY_LIVE_SET_INSERTED:
                admitted.insert(address)
            case DD_MEMORY_LIVE_SET_DROPPED:
                rejected += 1
            default:
                XCTFail("Unexpected insertion result")
            }
        }

        XCTAssertGreaterThan(admitted.count, Int(DD_MEMORY_LIVE_SET_CAPACITY) * 3 / 4)
        XCTAssertGreaterThan(rejected, 0)
        XCTAssertEqual(Set(snapshot().map { UInt(bitPattern: $0.address) }), admitted)
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.peak_occupancy, UInt64(admitted.count))
        XCTAssertEqual(diagnostics.dropped_samples, UInt64(rejected))
        XCTAssertTrue(diagnostics.reached_admission_limit)
    }

    func testConcurrentRealObjectCyclesAndSnapshots() {
        let workerCount = 8
        let cyclesPerWorker = 10_000
        let counts = LiveSetStressCounts()
        guard let table else {
            XCTFail("Live set allocation failed")
            return
        }
        let handle = LiveSetHandle(table: table, generation: generation)
        runConcurrentWorkers(count: workerCount, work: { worker in
            var inserted = 0
            var removed = 0
            var failed = 0
            for _ in 0..<cyclesPerWorker {
                let object: AnyObject = worker.isMultiple(of: 2) ? NSObject() : LiveSetSwiftObject()
                var sample = Self.sample(for: object, worker: worker)
                if dd_memory_live_set_insert(handle.table, handle.generation, &sample) == DD_MEMORY_LIVE_SET_INSERTED {
                    inserted += 1
                    if dd_memory_live_set_remove(handle.table, handle.generation, sample.address) {
                        removed += 1
                    } else {
                        failed += 1
                    }
                }
                withExtendedLifetime(object) {}
            }
            counts.record(inserted: inserted, removed: removed, failed: failed)
        }) { _ in
            for _ in 0..<100 {
                let samples = snapshot()
                XCTAssertEqual(Set(samples.map { UInt(bitPattern: $0.address) }).count, samples.count)
                XCTAssertTrue(samples.allSatisfy { (1...UInt64(workerCount)).contains($0.size) })
            }
        }
        let totals = counts.snapshot()
        XCTAssertEqual(totals.failed, 0)
        XCTAssertEqual(totals.inserted, totals.removed)
        XCTAssertTrue(snapshot().isEmpty)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).occupancy, 0)
    }

    func testConcurrentChurnSnapshotsAndSharedRemovalsOnSaturatedTable() {
        guard let table else {
            XCTFail("Live set allocation failed")
            return
        }
        let capacity = Int(DD_MEMORY_LIVE_SET_CAPACITY)
        let addresses = fillTableWithOneEntryPerBucket()
        guard addresses.count == capacity else {
            return
        }
        XCTAssertEqual(insert(0x2000_0000, size: 1), DD_MEMORY_LIVE_SET_DROPPED)
        for index in addresses.indices where index.isMultiple(of: 8) {
            XCTAssertTrue(remove(addresses[index]))
        }
        let churnAddresses = addresses.enumerated().filter { $0.offset % 8 == 1 }.map(\.element)
        let fixedAddresses = Set(addresses.enumerated().filter { $0.offset % 8 > 1 }.map(\.element))
        let initialOccupancy = capacity - capacity / 8
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).tombstones, UInt64(capacity / 8))

        // Phase 1: workers churn separate address sets while snapshots check that fixed residents remain intact.
        let workerCount = 8
        let cyclesPerWorker = 10_000
        let residentsPerWorker = churnAddresses.count / workerCount
        let handle = LiveSetHandle(table: table, generation: generation)
        let counts = LiveSetStressCounts()
        var overlappingSnapshots = 0
        runConcurrentWorkers(count: workerCount, work: { worker in
            let first = worker * residentsPerWorker
            var residents = Array(churnAddresses[first..<(first + residentsPerWorker)])
            var inserted = 0
            var removed = 0
            var failed = 0
            for cycle in 0..<cyclesPerWorker {
                let position = cycle % residents.count
                if residents[position] != 0 {
                    if dd_memory_live_set_remove(
                        handle.table, handle.generation, UnsafeRawPointer(bitPattern: residents[position])
                    ) {
                        removed += 1
                        residents[position] = 0
                    } else {
                        failed += 1
                        continue
                    }
                }
                let address = UInt(0x3000_0000 + (worker * cyclesPerWorker + cycle) * 16)
                var entry = Self.taggedSample(at: address)
                switch dd_memory_live_set_insert(handle.table, handle.generation, &entry) {
                case DD_MEMORY_LIVE_SET_INSERTED:
                    inserted += 1
                    residents[position] = address
                case DD_MEMORY_LIVE_SET_DROPPED:
                    break
                default:
                    failed += 1
                }
                if dd_memory_live_set_remove(
                    handle.table, handle.generation, UnsafeRawPointer(bitPattern: 0x4000_0000 + cycle * 16)
                ) {
                    failed += 1
                }
            }
            counts.record(inserted: inserted, removed: removed, failed: failed, addresses: residents.filter { $0 != 0 })
        }) { workersAreRunning in
            for _ in 0..<100 {
                if workersAreRunning() { overlappingSnapshots += 1 }
                let samples = snapshot()
                let capturedAddresses = Set(samples.map { UInt(bitPattern: $0.address) })
                XCTAssertEqual(capturedAddresses.count, samples.count)
                XCTAssertTrue(fixedAddresses.isSubset(of: capturedAddresses))
                XCTAssertLessThanOrEqual(samples.count, initialOccupancy)
                XCTAssertTrue(samples.allSatisfy {
                    $0.size == UInt64(UInt(bitPattern: $0.address)) &&
                    $0.frame_count == 2 && $0.frames.0 == $0.size && $0.frames.1 == ~$0.size
                })
            }
        }
        XCTAssertGreaterThan(overlappingSnapshots, 0)
        let totals = counts.snapshot()
        XCTAssertEqual(totals.failed, 0)
        XCTAssertGreaterThan(totals.inserted, 0)
        let expectedAddresses = fixedAddresses.union(totals.addresses)
        XCTAssertEqual(Set(snapshot().map { UInt(bitPattern: $0.address) }), expectedAddresses)
        XCTAssertEqual(expectedAddresses.count, initialOccupancy + totals.inserted - totals.removed)
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.occupancy, UInt64(expectedAddresses.count))
        XCTAssertEqual(diagnostics.tombstones, UInt64(capacity - expectedAddresses.count))
        XCTAssertEqual(diagnostics.duplicate_samples, 0)
        XCTAssertTrue(diagnostics.reached_admission_limit)

        // Phase 2: all workers remove the same remaining addresses; each address must be removed exactly once.
        let sharedAddresses = Array(expectedAddresses)
        let removals = LiveSetStressCounts()
        runConcurrentWorkers(count: workerCount, work: { _ in
            var removed = 0
            for address in sharedAddresses {
                if dd_memory_live_set_remove(handle.table, handle.generation, UnsafeRawPointer(bitPattern: address)) {
                    removed += 1
                }
            }
            removals.record(inserted: 0, removed: removed, failed: 0)
        }) { _ in
            for _ in 0..<20 {
                let samples = snapshot()
                XCTAssertEqual(Set(samples.map { UInt(bitPattern: $0.address) }).count, samples.count)
            }
        }
        XCTAssertEqual(removals.snapshot().removed, expectedAddresses.count)
        XCTAssertTrue(snapshot().isEmpty)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).occupancy, 0)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).tombstones, UInt64(capacity))
    }

    func testConcurrentCyclesRemainSafeAcrossStopAndRestart() {
        let workerCount = 8
        let cyclesPerWorker = 10_000
        guard let table else {
            XCTFail("Live set allocation failed")
            return
        }
        let handle = LiveSetHandle(table: table, generation: generation)
        runConcurrentWorkers(count: workerCount, work: { worker in
            for _ in 0..<cyclesPerWorker {
                let object: AnyObject = worker.isMultiple(of: 2) ? NSObject() : LiveSetSwiftObject()
                var sample = Self.sample(for: object, worker: worker)
                let token = dd_memory_live_set_diagnostics(handle.table).generation
                if dd_memory_live_set_insert(handle.table, token, &sample) == DD_MEMORY_LIVE_SET_INSERTED {
                    _ = dd_memory_live_set_remove(handle.table, token, sample.address)
                }
                withExtendedLifetime(object) {}
            }
        }) { _ in
            for _ in 0..<20 {
                let samples = snapshot()
                XCTAssertEqual(Set(samples.map { UInt(bitPattern: $0.address) }).count, samples.count)
                dd_memory_live_set_stop(table)
                generation = dd_memory_live_set_start(table)
                XCTAssertNotEqual(generation, 0)
            }
        }
        XCTAssertTrue(snapshot().isEmpty)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).occupancy, 0)

        XCTAssertEqual(insert(0x90000, size: 9), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(snapshot().map(\.size), [9])
        XCTAssertTrue(remove(0x90000))
    }

    private func runConcurrentWorkers(
        count: Int,
        work: @escaping @Sendable (Int) -> Void,
        whileWorkersRun: (_ workersAreRunning: () -> Bool) -> Void
    ) {
        let ready = DispatchGroup()
        let finished = DispatchGroup()
        let start = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "memory-live-set-stress", attributes: .concurrent)
        defer { finished.wait() }
        for worker in 0..<count {
            ready.enter()
            finished.enter()
            queue.async {
                ready.leave()
                start.wait()
                work(worker)
                finished.leave()
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
        for _ in 0..<count { start.signal() }
        whileWorkersRun { finished.wait(timeout: .now()) == .timedOut }
        XCTAssertEqual(finished.wait(timeout: .now() + 60), .success)
    }

    private static func sample(for object: AnyObject, worker: Int) -> dd_memory_live_sample_t {
        var entry = dd_memory_live_sample_t()
        entry.address = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
        entry.size = UInt64(worker + 1)
        entry.weight = 1
        entry.source = worker.isMultiple(of: 2) ? DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC : DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
        return entry
    }

    private func fillTableWithOneEntryPerBucket(
        makeSample: (UInt) -> dd_memory_live_sample_t = MemoryLiveSetTests.taggedSample
    ) -> [UInt] {
        let addresses = addressesForEveryBucket()
        for address in addresses {
            var entry = makeSample(address)
            let result = dd_memory_live_set_insert(table, generation, &entry)
            XCTAssertEqual(result, DD_MEMORY_LIVE_SET_INSERTED)
            guard result == DD_MEMORY_LIVE_SET_INSERTED else {
                return []
            }
        }
        return addresses
    }

    private func insert(_ address: UInt, size: UInt64) -> dd_memory_live_insert_result_t {
        var entry = sample(at: address, size: size)
        return dd_memory_live_set_insert(table, generation, &entry)
    }

    private func remove(_ address: UInt) -> Bool {
        dd_memory_live_set_remove(table, generation, UnsafeRawPointer(bitPattern: address))
    }

    private func sample(at address: UInt, size: UInt64) -> dd_memory_live_sample_t {
        var entry = dd_memory_live_sample_t()
        entry.address = UnsafeRawPointer(bitPattern: address)
        entry.size = size
        entry.weight = 1
        return entry
    }

    // Sample copies still borrow class-name bytes until the next capture.
    private func snapshot() -> [dd_memory_live_sample_t] {
        let view = captureSnapshot()
        return Array(UnsafeBufferPointer(start: view.samples, count: view.count))
    }

    private func captureSnapshot() -> dd_memory_live_snapshot_view_t {
        XCTAssertTrue(dd_memory_live_set_snapshot(table, generation, snapshotStorage))
        return dd_memory_live_snapshot_view(snapshotStorage)
    }

    private static func taggedSample(at address: UInt) -> dd_memory_live_sample_t {
        var entry = dd_memory_live_sample_t()
        entry.address = UnsafeRawPointer(bitPattern: address)
        entry.size = UInt64(address)
        entry.weight = 1
        entry.frame_count = 2
        entry.frames.0 = entry.size
        entry.frames.1 = ~entry.size
        return entry
    }

    private func addressesForEveryBucket() -> [UInt] {
        var addresses = Array(repeating: UInt(0), count: Int(DD_MEMORY_LIVE_SET_CAPACITY))
        var remaining = addresses.count
        for index in 0..<1_000_000 {
            let address = UInt(0x10_0000 + index * 16)
            let bucket = dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: address))
            if addresses[bucket] == 0 {
                addresses[bucket] = address
                remaining -= 1
                if remaining == 0 {
                    return addresses
                }
            }
        }
        XCTFail("Could not construct one address per bucket")
        return []
    }

    private func collidingAddresses(count: Int, bucket: Int? = nil) -> [UInt] {
        let first = UInt(0x10_0000)
        let bucket = bucket ?? dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: first))
        var result: [UInt] = []
        for index in 0..<1_000_000 {
            let address = first + UInt(index) * 16
            if dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: address)) == bucket {
                result.append(address)
                if result.count == count {
                    return result
                }
            }
        }
        return result
    }
}

private final class LiveSetSwiftObject {
    let payload = (1, 2, 3, 4)
}

private struct LiveSetHandle: @unchecked Sendable {
    let table: OpaquePointer
    let generation: UInt64
}

private final class LiveSetStressCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var inserted = 0
    private var removed = 0
    private var failed = 0
    private var addresses: [UInt] = []

    func record(inserted: Int, removed: Int, failed: Int, addresses: [UInt] = []) {
        lock.lock()
        self.inserted += inserted
        self.removed += removed
        self.failed += failed
        self.addresses.append(contentsOf: addresses)
        lock.unlock()
    }

    func snapshot() -> (inserted: Int, removed: Int, failed: Int, addresses: [UInt]) {
        lock.lock()
        defer { lock.unlock() }
        return (inserted, removed, failed, addresses)
    }
}

#endif // !os(watchOS)
