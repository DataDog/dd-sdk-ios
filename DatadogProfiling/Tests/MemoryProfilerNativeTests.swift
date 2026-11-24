/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)
import Foundation
import XCTest
import DatadogMachProfiler.Testing

// swiftlint:disable duplicate_imports
import DatadogMachProfiler.Pprof
// swiftlint:enable duplicate_imports

final class MemoryProfilerNativeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        dd_memory_profiler_reset_for_testing()
        XCTAssertTrue(dd_memory_profiler_start_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED))
    }

    override func tearDown() {
        dd_memory_profiler_reset_for_testing()
        super.tearDown()
    }

    func testConsumingDiagnosticsPreservesLiveObjectsAndDoesNotRepeatCounts() throws {
        record(address: 0x10000, size: 16)
        var first = capture(expected: DD_MEMORY_CAPTURE_READY)
        _ = try serializedData(&first)
        let diagnostics = dd_memory_profiler_consume_diagnostics()
        XCTAssertEqual(diagnostics.sampled_allocations, 1)
        XCTAssertEqual(diagnostics.window.recorded_allocations, 1)
        XCTAssertEqual(diagnostics.window.live_set.occupancy, 1)
        XCTAssertGreaterThan(diagnostics.encoder_storage_bytes, 0)

        let consumed = dd_memory_profiler_consume_diagnostics()
        XCTAssertEqual(consumed.sampled_allocations, 0)
        XCTAssertEqual(consumed.window.recorded_allocations, 0)
        XCTAssertEqual(consumed.window.live_set.probe_count, 0)
        XCTAssertEqual(consumed.window.live_set.occupancy, 1)
        XCTAssertEqual(capture(expected: DD_MEMORY_CAPTURE_IDLE).aggregation.count, 1)

        record(address: 0x20000, size: 8)
        dd_memory_profiler_stop()
        let stopped = dd_memory_profiler_consume_diagnostics()
        XCTAssertEqual(stopped.sampled_allocations, 1)
        XCTAssertEqual(stopped.window.recorded_allocations, 1)
        XCTAssertEqual(stopped.window.live_set.occupancy, 2)
        XCTAssertGreaterThan(stopped.recorder_storage_bytes, 0)
        XCTAssertTrue(dd_memory_profiler_start_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED))
        record(address: 0x30000, size: 4)
        _ = capture(expected: DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(dd_memory_profiler_consume_diagnostics().window.recorded_allocations, 1)
    }

    func testAllocationsAfterCaptureBelongToTheFollowingDiagnosticsWindow() throws {
        record(address: 0x10000, size: 16)
        var first = capture(expected: DD_MEMORY_CAPTURE_READY)
        record(address: 0x20000, size: 32)
        _ = try serializedData(&first)
        let closed = dd_memory_profiler_consume_diagnostics()
        XCTAssertEqual(closed.sampled_allocations, 1)
        XCTAssertEqual(closed.window.recorded_allocations, 1)
        XCTAssertEqual(dd_memory_profiler_consume_diagnostics().sampled_allocations, 0)

        _ = capture(expected: DD_MEMORY_CAPTURE_READY)
        let following = dd_memory_profiler_consume_diagnostics()
        XCTAssertEqual(following.sampled_allocations, 1)
        XCTAssertEqual(following.window.recorded_allocations, 1)
        XCTAssertEqual(following.window.live_set.occupancy, 2)
    }

    func testLaunchRecordingStartsForEveryPositiveRate() {
        let suiteName = "MemoryProfilerNativeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for rate in [Double.leastNormalMagnitude, 1, 100] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            defaults.set(rate, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)

            dd_memory_profiler_auto_start_for_testing(suiteName, false, false)

            XCTAssertTrue(dd_memory_profiler_is_running(), "rate: \(rate)")
            XCTAssertTrue(dd_memory_profiler_was_started_at_launch(), "rate: \(rate)")
            XCTAssertNil(defaults.object(forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY))
            record(address: 0x10000, size: 8)
            assertTotals(
                capture(expected: DD_MEMORY_CAPTURE_READY),
                allocationObjects: 1,
                allocationBytes: 8,
                liveObjects: 1,
                liveBytes: 8
            )
        }
    }

    func testLaunchRecordingRejectsDisabledAndInvalidNumericRates() {
        let suiteName = "MemoryProfilerNativeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for rate in [0, -1, Double.infinity, -Double.infinity, Double.nan] {
            dd_memory_profiler_configure_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED)
            defaults.set(rate, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)

            dd_memory_profiler_auto_start_for_testing(suiteName, false, false)

            XCTAssertFalse(dd_memory_profiler_is_running(), "rate: \(rate)")
            XCTAssertFalse(dd_memory_profiler_was_started_at_launch(), "rate: \(rate)")
            XCTAssertNil(defaults.object(forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY))
        }
    }

    func testRepeatedStartAdoptsAllocationAndLiveStateAcrossCaptures() {
        record(address: 0x10000, size: 8, weight: 2.5)
        let origin = dd_memory_profiler_window_start_time_nanos()
        XCTAssertGreaterThan(origin, 0)
        XCTAssertTrue(dd_memory_profiler_start())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), origin)

        let first = capture(expected: DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(first.time_nanos, origin)
        XCTAssertGreaterThanOrEqual(first.duration_nanos, 0)
        assertTotals(first, allocationObjects: 2.5, allocationBytes: 20, liveObjects: 2.5, liveBytes: 20)

        record(address: 0x20000, size: 4, weight: 1.5)
        let second = capture(expected: DD_MEMORY_CAPTURE_READY)
        XCTAssertGreaterThanOrEqual(second.time_nanos, first.time_nanos)
        assertTotals(second, allocationObjects: 1.5, allocationBytes: 6, liveObjects: 4, liveBytes: 26)
        _ = capture(expected: DD_MEMORY_CAPTURE_IDLE)
    }

    func testSerializedCapturesOwnIndependentDataAcrossWindowsAndRestart() throws {
        record(address: 0x10000, size: 8, weight: 2.5)
        var first = capture(expected: DD_MEMORY_CAPTURE_READY)
        let firstData = try serializedData(&first)
        let firstProfile = try decode(firstData)
        XCTAssertEqual(firstProfile.time, first.time_nanos)
        XCTAssertEqual(firstProfile.duration, first.duration_nanos)
        XCTAssertEqual(firstProfile.values, [3, 20, 3, 20])

        record(address: 0x20000, size: 4, weight: 1.5)
        var second = capture(expected: DD_MEMORY_CAPTURE_READY)
        let secondData = try serializedData(&second)
        XCTAssertEqual(try decode(secondData).values, [2, 6, 4, 26])

        dd_memory_profiler_stop()
        XCTAssertTrue(dd_memory_profiler_start_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED))
        record(address: 0x30000, size: 7)
        var restarted = capture(expected: DD_MEMORY_CAPTURE_READY)
        let restartedData = try serializedData(&restarted)
        XCTAssertEqual(try decode(restartedData).values, [1, 7, 1, 7])
        dd_memory_profiler_stop()

        let preserved = try decode(firstData)
        XCTAssertEqual(preserved.time, first.time_nanos)
        XCTAssertEqual(preserved.duration, first.duration_nanos)
        XCTAssertEqual(preserved.values, [3, 20, 3, 20])
        XCTAssertEqual(try decode(secondData).values, [2, 6, 4, 26])
    }

    func testSerializationRejectsInvalidCapturesAndCanRecover() throws {
        XCTAssertNil(dd_memory_profiler_serialize(nil).data)
        record(address: 0x10000, size: 8)
        var valid = capture(expected: DD_MEMORY_CAPTURE_READY)
        XCTAssertFalse(try serializedData(&valid).isEmpty)
        var invalid = valid
        invalid.time_nanos = -1
        let failed = dd_memory_profiler_serialize(&invalid)
        XCTAssertNil(failed.data)
        XCTAssertEqual(failed.size, 0)
        XCTAssertEqual(try decode(serializedData(&valid)).values, [1, 8, 1, 8])

        dd_memory_profiler_stop()
        let stopped = dd_memory_profiler_serialize(&valid)
        XCTAssertNil(stopped.data)
        XCTAssertEqual(stopped.size, 0)
    }

    func testLastFreeSerializesEmptyReadyProfileBeforeBecomingIdle() throws {
        record(address: 0x10000, size: 8)
        var populated = capture(expected: DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(try decode(serializedData(&populated)).values, [1, 8, 1, 8])

        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        var empty = capture(expected: DD_MEMORY_CAPTURE_READY)
        XCTAssertEqual(empty.aggregation.count, 0)
        let data = try serializedData(&empty)
        let decoded = try data.withUnsafeBytes { bytes in
            try XCTUnwrap(perftools__profiles__profile__unpack(
                nil,
                bytes.count,
                bytes.bindMemory(to: UInt8.self).baseAddress
            ))
        }
        defer { perftools__profiles__profile__free_unpacked(decoded, nil) }
        let profile = decoded.pointee
        let strings = (0..<profile.n_string_table).map { String(cString: profile.string_table[$0]!) }
        let sampleTypes = (0..<profile.n_sample_type).map { profile.sample_type[$0]!.pointee }
        XCTAssertEqual(sampleTypes.map { strings[Int($0.type)] }, ["alloc_objects", "alloc_space", "inuse_objects", "inuse_space"])
        XCTAssertEqual(sampleTypes.map { strings[Int($0.unit)] }, ["count", "bytes", "count", "bytes"])
        XCTAssertEqual(profile.n_sample, 0)
        XCTAssertEqual(profile.n_location, 0)
        XCTAssertEqual(profile.n_mapping, 0)
        XCTAssertEqual(profile.time_nanos, empty.time_nanos)
        XCTAssertEqual(profile.duration_nanos, empty.duration_nanos)
        XCTAssertEqual(strings[Int(profile.default_sample_type)], "inuse_space")
        _ = capture(expected: DD_MEMORY_CAPTURE_IDLE)
    }

    func testPauseDrainsAllocationsKeepsFreesAndReportsLastFreeAsReady() {
        record(address: 0x10000, size: 8)
        dd_memory_profiler_pause()
        XCTAssertTrue(dd_memory_profiler_is_running())
        XCTAssertTrue(dd_memory_profiler_is_paused())
        record(address: 0x20000, size: 16)
        let paused = capture(expected: DD_MEMORY_CAPTURE_READY)
        assertTotals(paused, allocationObjects: 1, allocationBytes: 8, liveObjects: 1, liveBytes: 8)
        let frozen = capture(expected: DD_MEMORY_CAPTURE_IDLE)
        XCTAssertEqual(frozen.duration_nanos, 0)

        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))
        XCTAssertEqual(capture(expected: DD_MEMORY_CAPTURE_READY).aggregation.count, 0)
        _ = capture(expected: DD_MEMORY_CAPTURE_IDLE)
        dd_memory_profiler_resume()
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertGreaterThanOrEqual(
            dd_memory_profiler_window_start_time_nanos(),
            paused.time_nanos + paused.duration_nanos
        )
        record(address: 0x30000, size: 7)
        assertTotals(
            capture(expected: DD_MEMORY_CAPTURE_READY),
            allocationObjects: 1,
            allocationBytes: 7,
            liveObjects: 1,
            liveBytes: 7
        )
    }

    func testFullStopAndRestartClearAllocationsAndLiveState() {
        record(address: 0x10000, size: 8)
        dd_memory_profiler_pause()
        dd_memory_profiler_stop()
        dd_memory_profiler_stop()
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertFalse(dd_memory_profiler_is_paused())
        XCTAssertEqual(dd_memory_profiler_window_start_time_nanos(), 0)
        _ = capture(expected: DD_MEMORY_CAPTURE_FAILED)
        record(address: 0x20000, size: 32)
        dd_memory_profiler_remove_for_testing(UnsafeRawPointer(bitPattern: 0x10000))

        XCTAssertTrue(dd_memory_profiler_start_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED))
        _ = capture(expected: DD_MEMORY_CAPTURE_IDLE)
        record(address: 0x10000, size: 3, weight: 2)
        assertTotals(
            capture(expected: DD_MEMORY_CAPTURE_READY),
            allocationObjects: 2,
            allocationBytes: 6,
            liveObjects: 2,
            liveBytes: 6
        )
    }

    func testEitherHookFailureDisablesBothAndAllowsRestart() {
        for failure in [DD_MEMORY_TEST_SWIFT_HOOK_FAILS, DD_MEMORY_TEST_OBJC_HOOK_FAILS] {
            dd_memory_profiler_stop()
            XCTAssertFalse(dd_memory_profiler_start_for_testing(failure))
            XCTAssertFalse(dd_memory_profiler_is_running())
            XCTAssertFalse(dd_swift_alloc_hook_diagnostics().is_enabled)
            XCTAssertFalse(dd_objc_alloc_hook_diagnostics().is_enabled)
            _ = capture(expected: DD_MEMORY_CAPTURE_FAILED)
            XCTAssertTrue(dd_memory_profiler_start_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED))
            _ = capture(expected: DD_MEMORY_CAPTURE_IDLE)
        }
    }

    func testConcurrentObserversOverlapPauseCaptureStopAndRestart() {
        let workers = DispatchGroup()
        let began = DispatchGroup()
        let queue = DispatchQueue(label: "memory-profiler-native-stress", attributes: .concurrent)
        defer { workers.wait() }
        for worker in 0..<8 {
            workers.enter()
            began.enter()
            queue.async {
                for iteration in 0..<20_000 {
                    var sample = dd_memory_live_sample_t()
                    // Per-worker addresses avoid removing another producer's entry.
                    sample.address = UnsafeRawPointer(bitPattern: 0x10000 + worker * 16)
                    sample.size = UInt64(worker + 1)
                    sample.weight = 1
                    dd_memory_profiler_record_for_testing(&sample)
                    dd_memory_profiler_remove_for_testing(sample.address)
                    if iteration == 0 {
                        began.leave()
                    }
                }
                workers.leave()
            }
        }
        XCTAssertEqual(began.wait(timeout: .now() + 10), .success)
        var overlappingTransitions = 0
        for _ in 0..<12 {
            if workers.wait(timeout: .now()) == .timedOut {
                overlappingTransitions += 1
            }
            dd_memory_profiler_pause()
            _ = capture()
            dd_memory_profiler_resume()
            dd_memory_profiler_stop()
            XCTAssertTrue(dd_memory_profiler_start_for_testing(DD_MEMORY_TEST_HOOKS_SUCCEED))
        }
        XCTAssertEqual(workers.wait(timeout: .now() + 60), .success)
        XCTAssertGreaterThan(overlappingTransitions, 0)
        dd_memory_profiler_pause()
        let final = capture()
        let samples = UnsafeBufferPointer(start: final.aggregation.samples, count: final.aggregation.count)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.inuse_objects }, 0, accuracy: 1e-6)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.inuse_space }, 0, accuracy: 1e-6)
        _ = capture(expected: DD_MEMORY_CAPTURE_IDLE)
    }

    func testRealSwiftObserverRecordsAndRemovesLargeAllocationWhilePaused() throws {
        dd_memory_profiler_stop()
        XCTAssertTrue(dd_memory_profiler_start())
        let metadata = unsafeBitCast(MemoryProfilerNativeSwiftFixture.self, to: UnsafeRawPointer.self)
        let size = 16 * 1_024 * 1_024
        let address = try XCTUnwrap(dd_swift_alloc_object_for_testing(metadata, size, 15))
        dd_memory_profiler_pause()
        let first = capture(expected: DD_MEMORY_CAPTURE_READY)
        let samples = UnsafeBufferPointer(start: first.aggregation.samples, count: first.aggregation.count)
        let target = samples.first { $0.key.swift_metadata == OpaquePointer(metadata) }
        XCTAssertNotNil(target)
        XCTAssertGreaterThan(target?.key.frame_count ?? 0, 0)
        XCTAssertGreaterThan(target?.inuse_space ?? 0, 0)
        dd_swift_dealloc_uninitialized_object_for_testing(address, size, 15)
        let final = capture(expected: DD_MEMORY_CAPTURE_READY)
        let finalSamples = UnsafeBufferPointer(start: final.aggregation.samples, count: final.aggregation.count)
        XCTAssertFalse(finalSamples.contains { $0.key.swift_metadata == OpaquePointer(metadata) })
    }

    func testRealObjCObserverRecordsAndRemovesLargeAllocationWhilePaused() throws {
        dd_memory_profiler_stop()
        XCTAssertTrue(dd_memory_profiler_start())
        let object = try XCTUnwrap(dd_memory_profiler_allocate_objc_for_testing())
        dd_memory_profiler_pause()
        let first = capture(expected: DD_MEMORY_CAPTURE_READY)
        let samples = UnsafeBufferPointer(start: first.aggregation.samples, count: first.aggregation.count)
        let target = samples.first { sample in
            sample.key.class_name.map { String(cString: $0) } == "DDMemoryProfilerNativeLargeFixture"
        }
        XCTAssertNotNil(target)
        XCTAssertGreaterThan(target?.key.frame_count ?? 0, 0)
        XCTAssertGreaterThan(target?.inuse_space ?? 0, 0)
        dd_memory_profiler_release_objc_for_testing(object)
        let final = capture(expected: DD_MEMORY_CAPTURE_READY)
        let finalSamples = UnsafeBufferPointer(start: final.aggregation.samples, count: final.aggregation.count)
        XCTAssertFalse(finalSamples.contains { sample in
            sample.key.class_name.map { String(cString: $0) } == "DDMemoryProfilerNativeLargeFixture"
        })
    }

    private func record(address: UInt, size: UInt64, weight: Double = 1) {
        var sample = dd_memory_live_sample_t()
        sample.address = UnsafeRawPointer(bitPattern: address)
        sample.size = size
        sample.weight = weight
        dd_memory_profiler_record_for_testing(&sample)
    }

    private func serializedData(_ capture: inout dd_memory_capture_t) throws -> Data {
        let bytes = dd_memory_profiler_serialize(&capture)
        return Data(bytes: try XCTUnwrap(bytes.data), count: bytes.size)
    }

    private func decode(_ data: Data) throws -> (time: Int64, duration: Int64, values: [Int64]) {
        let profile = try data.withUnsafeBytes { bytes in
            try XCTUnwrap(perftools__profiles__profile__unpack(
                nil,
                bytes.count,
                bytes.bindMemory(to: UInt8.self).baseAddress
            ))
        }
        defer { perftools__profiles__profile__free_unpacked(profile, nil) }
        XCTAssertEqual(profile.pointee.n_sample, 1)
        let samples = try XCTUnwrap(profile.pointee.sample)
        let sample = try XCTUnwrap(samples.pointee).pointee
        return (
            profile.pointee.time_nanos,
            profile.pointee.duration_nanos,
            Array(UnsafeBufferPointer(start: sample.value, count: sample.n_value))
        )
    }

    private func capture(
        expected: dd_memory_capture_status_t? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> dd_memory_capture_t {
        var capture = dd_memory_capture_t()
        let status = dd_memory_profiler_capture(&capture)
        if let expected {
            XCTAssertEqual(status, expected, file: file, line: line)
        } else {
            XCTAssertNotEqual(status, DD_MEMORY_CAPTURE_FAILED, file: file, line: line)
        }
        return capture
    }

    private func assertTotals(
        _ capture: dd_memory_capture_t,
        allocationObjects: Double,
        allocationBytes: Double,
        liveObjects: Double,
        liveBytes: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let samples = UnsafeBufferPointer(start: capture.aggregation.samples, count: capture.aggregation.count)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.alloc_objects }, allocationObjects, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.alloc_space }, allocationBytes, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.inuse_objects }, liveObjects, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.inuse_space }, liveBytes, accuracy: 1e-6, file: file, line: line)
    }
}

private final class MemoryProfilerNativeSwiftFixture {
    var payload = 0
}

#endif // !os(watchOS) && !os(macOS)
