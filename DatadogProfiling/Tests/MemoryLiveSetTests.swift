/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest
import DatadogMachProfiler

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

    func record(inserted: Int, removed: Int, failed: Int) {
        lock.lock()
        self.inserted += inserted
        self.removed += removed
        self.failed += failed
        lock.unlock()
    }

    func snapshot() -> (inserted: Int, removed: Int, failed: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (inserted, removed, failed)
    }
}

final class MemoryLiveSetTests: XCTestCase {
    private var table: OpaquePointer?
    private var generation: UInt64 = 0

    override func setUp() {
        super.setUp()
        table = dd_memory_live_set_create()
        XCTAssertNotNil(table)
        generation = dd_memory_live_set_start(table)
        XCTAssertNotEqual(generation, 0)
    }

    override func tearDown() {
        dd_memory_live_set_stop(table)
        dd_memory_live_set_destroy(table)
        table = nil
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

    func testRestartRejectsStaleWorkAndClearsSamples() {
        XCTAssertEqual(insert(0x10000, size: 42), DD_MEMORY_LIVE_SET_INSERTED)
        let oldGeneration = generation
        dd_memory_live_set_stop(table)
        generation = dd_memory_live_set_start(table)
        XCTAssertNotEqual(generation, oldGeneration)
        XCTAssertTrue(snapshot().isEmpty)

        var staleSample = sample(at: 0x20000, size: 64)
        let staleResult = dd_memory_live_set_insert(table, oldGeneration, &staleSample)
        XCTAssertEqual(staleResult, DD_MEMORY_LIVE_SET_STALE_GENERATION)
        let staleAddress = UnsafeRawPointer(bitPattern: 0x10000)
        XCTAssertFalse(dd_memory_live_set_remove(table, oldGeneration, staleAddress))
        XCTAssertTrue(snapshot().isEmpty)
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.stale_generation_rejections, 2)
        XCTAssertEqual(diagnostics.dropped_samples, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.generation_transitions, 3)
    }

    func testShortSnapshotFailsWithoutPartialResults() {
        XCTAssertEqual(insert(0x10000, size: 1), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(insert(0x20000, size: 2), DD_MEMORY_LIVE_SET_INSERTED)
        let output = UnsafeMutablePointer<dd_memory_live_sample_t>.allocate(capacity: 1)
        output.initialize(to: dd_memory_live_sample_t())
        defer {
            output.deinitialize(count: 1)
            output.deallocate()
        }
        var count = 99
        XCTAssertFalse(dd_memory_live_set_snapshot(table, generation, output, 1, nil, 0, &count, nil))
        XCTAssertEqual(count, 0)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).snapshot_failures, 1)
        XCTAssertEqual(Set(snapshot().map { $0.size }), [1, 2])
        let expectedBytes = UInt64(DD_MEMORY_LIVE_SET_CAPACITY) *
            UInt64(MemoryLayout<dd_memory_live_sample_t>.stride)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).snapshot_bytes_high_water, expectedBytes)
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
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "memory-live-set-stress", attributes: .concurrent)

        for worker in 0..<workerCount {
            group.enter()
            queue.async {
                var localInserted = 0
                var localRemoved = 0
                var localFailures = 0
                for _ in 0..<cyclesPerWorker {
                    let object: AnyObject = worker.isMultiple(of: 2)
                        ? NSObject()
                        : LiveSetSwiftObject()
                    let address = Unmanaged.passUnretained(object).toOpaque()
                    var sample = dd_memory_live_sample_t()
                    sample.address = UnsafeRawPointer(address)
                    sample.size = UInt64(worker + 1)
                    sample.weight = 1
                    sample.source = worker.isMultiple(of: 2)
                        ? DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
                        : DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT
                    let result = dd_memory_live_set_insert(handle.table, handle.generation, &sample)
                    if result == DD_MEMORY_LIVE_SET_INSERTED {
                        localInserted += 1
                        if dd_memory_live_set_remove(handle.table, handle.generation, sample.address) {
                            localRemoved += 1
                        } else {
                            localFailures += 1
                        }
                    }
                    withExtendedLifetime(object) {}
                }
                counts.record(inserted: localInserted, removed: localRemoved, failed: localFailures)
                group.leave()
            }
        }

        for _ in 0..<100 {
            let samples = snapshot()
            XCTAssertEqual(Set(samples.map { UInt(bitPattern: $0.address) }).count, samples.count)
            XCTAssertTrue(samples.allSatisfy { (1...UInt64(workerCount)).contains($0.size) })
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        let totals = counts.snapshot()
        XCTAssertEqual(totals.failed, 0)
        XCTAssertEqual(totals.inserted, totals.removed)
        XCTAssertTrue(snapshot().isEmpty)
        let diagnostics = dd_memory_live_set_diagnostics(table)
        XCTAssertEqual(diagnostics.occupancy, 0)
        XCTAssertLessThanOrEqual(diagnostics.max_probe_length, UInt64(DD_MEMORY_LIVE_SET_MAX_PROBE))
    }

    func testConcurrentCyclesRemainSafeAcrossStopAndRestart() {
        let workerCount = 8
        let cyclesPerWorker = 10_000
        guard let table else {
            XCTFail("Live set allocation failed")
            return
        }
        let handle = LiveSetHandle(table: table, generation: generation)
        let ready = DispatchGroup()
        let finished = DispatchGroup()
        let gate = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "memory-live-set-restarts", attributes: .concurrent)

        for worker in 0..<workerCount {
            ready.enter()
            finished.enter()
            queue.async {
                ready.leave()
                gate.wait()
                for _ in 0..<cyclesPerWorker {
                    let object: AnyObject = worker.isMultiple(of: 2)
                        ? NSObject()
                        : LiveSetSwiftObject()
                    var sample = dd_memory_live_sample_t()
                    sample.address = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
                    sample.size = UInt64(worker + 1)
                    sample.weight = 1
                    let token = dd_memory_live_set_diagnostics(handle.table).generation
                    if dd_memory_live_set_insert(handle.table, token, &sample) ==
                        DD_MEMORY_LIVE_SET_INSERTED {
                        _ = dd_memory_live_set_remove(handle.table, token, sample.address)
                    }
                    withExtendedLifetime(object) {}
                }
                finished.leave()
            }
        }

        XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
        for _ in 0..<workerCount {
            gate.signal()
        }
        for _ in 0..<20 {
            let samples = snapshot()
            XCTAssertEqual(Set(samples.map { UInt(bitPattern: $0.address) }).count, samples.count)
            dd_memory_live_set_stop(table)
            generation = dd_memory_live_set_start(table)
            XCTAssertNotEqual(generation, 0)
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 60), .success)
        XCTAssertTrue(snapshot().isEmpty)
        XCTAssertEqual(dd_memory_live_set_diagnostics(table).occupancy, 0)

        XCTAssertEqual(insert(0x90000, size: 9), DD_MEMORY_LIVE_SET_INSERTED)
        XCTAssertEqual(snapshot().map(\.size), [9])
        XCTAssertTrue(remove(0x90000))
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

    private func snapshot() -> [dd_memory_live_sample_t] {
        let capacity = Int(DD_MEMORY_LIVE_SET_CAPACITY)
        let output = UnsafeMutablePointer<dd_memory_live_sample_t>.allocate(capacity: capacity)
        output.initialize(repeating: dd_memory_live_sample_t(), count: capacity)
        defer {
            output.deinitialize(count: capacity)
            output.deallocate()
        }
        var count = 0
        XCTAssertTrue(dd_memory_live_set_snapshot(
            table, generation, output, capacity, nil, 0, &count, nil
        ))
        return Array(UnsafeBufferPointer(start: output, count: count))
    }

    private func collidingAddresses(count: Int) -> [UInt] {
        let first = UInt(0x10_0000)
        let bucket = dd_memory_live_set_bucket(UnsafeRawPointer(bitPattern: first))
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
#endif // !os(watchOS)
