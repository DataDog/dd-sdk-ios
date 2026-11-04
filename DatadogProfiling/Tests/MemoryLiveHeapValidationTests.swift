/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import Foundation
import XCTest
// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports

@objc(DDMemoryLiveHeapValidationObject)
private final class MemoryLiveHeapValidationObject: NSObject {}

private final class MemoryLiveHeapValidationSwiftObject {
    let value = 42
}

/// Exercises the production owner with the reviewed hooks, sampler and recorder connected.
final class MemoryLiveHeapValidationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        dd_memory_test_reset()
        // Initialize fixture metadata before forcing a particular allocation to be sampled.
        withExtendedLifetime(MemoryLiveHeapValidationObject()) {}
        withExtendedLifetime(MemoryLiveHeapValidationSwiftObject()) {}
    }

    override func tearDown() {
        dd_memory_test_reset()
        super.tearDown()
    }

    func testObjectiveCAllocationAndDeallocationReachTheRecorder() {
        XCTAssertTrue(dd_memory_profiler_start())
        dd_memory_test_force_next_sample()
        var object: MemoryLiveHeapValidationObject? = MemoryLiveHeapValidationObject()
        weak var weakObject = object

        XCTAssertEqual(totals(for: "DDMemoryLiveHeapValidationObject").inuseObjects, 1)
        withExtendedLifetime(object) {}
        object = nil
        XCTAssertNil(weakObject)
        XCTAssertEqual(totals(for: "DDMemoryLiveHeapValidationObject").inuseObjects, 0)
    }

    func testSwiftAllocationAndDeallocationReachTheRecorder() {
        XCTAssertTrue(dd_memory_profiler_start())
        dd_memory_test_force_next_sample()
        var object: MemoryLiveHeapValidationSwiftObject? = MemoryLiveHeapValidationSwiftObject()
        weak var weakObject = object

        XCTAssertEqual(totals(for: "MemoryLiveHeapValidationSwiftObject").inuseObjects, 1)
        withExtendedLifetime(object) {}
        object = nil
        XCTAssertNil(weakObject)
        XCTAssertEqual(totals(for: "MemoryLiveHeapValidationSwiftObject").inuseObjects, 0)
    }

    func testTriggeredCapturePreservesThePeriodicAllocationDelta() {
        XCTAssertTrue(dd_memory_profiler_start())
        recordFixture(weight: 1.25)

        let firstTrigger = totals(for: "OwnerCaptureFixture")
        let secondTrigger = totals(for: "OwnerCaptureFixture")
        XCTAssertEqual(firstTrigger.inuseObjects, 1.25)
        XCTAssertEqual(firstTrigger.allocObjects, 0)
        XCTAssertEqual(secondTrigger.inuseObjects, 1.25)
        XCTAssertEqual(secondTrigger.allocObjects, 0)

        let periodic = totals(for: "OwnerCaptureFixture", drainingAllocations: true)
        XCTAssertEqual(periodic.inuseObjects, 1.25)
        XCTAssertEqual(periodic.allocObjects, 1.25)
        XCTAssertEqual(periodic.allocSpace, 100)

        let nextPeriodic = totals(for: "OwnerCaptureFixture", drainingAllocations: true)
        XCTAssertEqual(nextPeriodic.inuseObjects, 1.25)
        XCTAssertEqual(nextPeriodic.allocObjects, 0)
    }

    func testStopAndRestartClearPreviousGeneration() {
        XCTAssertTrue(dd_memory_profiler_start())
        let previousGeneration = dd_memory_test_session_generation()
        recordFixture(weight: 1)
        XCTAssertEqual(totals(for: "OwnerCaptureFixture").inuseObjects, 1)

        dd_memory_profiler_stop()
        XCTAssertFalse(dd_memory_profiler_is_running())
        XCTAssertTrue(dd_memory_profiler_start())
        XCTAssertNotEqual(dd_memory_test_session_generation(), previousGeneration)
        XCTAssertEqual(totals(for: "OwnerCaptureFixture", drainingAllocations: true).inuseObjects, 0)
    }

    func testFailedStartLeavesBothObservationPathsStopped() {
        dd_memory_test_force_start_failure(true)
        XCTAssertFalse(dd_memory_profiler_start())
        XCTAssertFalse(dd_memory_profiler_is_running())
        dd_memory_test_force_start_failure(false)
        XCTAssertTrue(dd_memory_profiler_start())
        XCTAssertTrue(dd_memory_profiler_is_running())
    }

    func testConcurrentHookTrafficAndCaptureReleaseAllFixtureObjects() {
        XCTAssertTrue(dd_memory_profiler_start())
        let group = DispatchGroup()
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<500 {
                    autoreleasepool {
                        dd_memory_test_force_next_sample()
                        withExtendedLifetime(MemoryLiveHeapValidationObject()) {}
                        dd_memory_test_force_next_sample()
                        withExtendedLifetime(MemoryLiveHeapValidationSwiftObject()) {}
                    }
                }
                group.leave()
            }
        }

        // Captures overlap the same recorder's allocation and deallocation mutations.
        for index in 0..<50 {
            _ = capture(drainingAllocations: index.isMultiple(of: 2))
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(totals(for: "DDMemoryLiveHeapValidationObject").inuseObjects, 0)
        XCTAssertEqual(totals(for: "MemoryLiveHeapValidationSwiftObject").inuseObjects, 0)
    }

    private func recordFixture(weight: Double) {
        var sample = dd_memory_live_sample_t()
        sample.address = UnsafeRawPointer(bitPattern: 0x10000)
        sample.size = 80
        sample.weight = weight
        sample.source = DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC
        sample.frame_count = 1
        sample.frames.0 = 0x1234
        "OwnerCaptureFixture".withCString { name in
            sample.class_name = name
            _ = dd_memory_test_record_sample(&sample, dd_memory_test_session_generation())
        }
    }

    private func totals(
        for name: String,
        drainingAllocations: Bool = false
    ) -> (allocObjects: Double, allocSpace: Double, inuseObjects: Double) {
        let view = capture(drainingAllocations: drainingAllocations)
        guard let samples = view.samples else {
            return (0, 0, 0)
        }
        var result = (allocObjects: 0.0, allocSpace: 0.0, inuseObjects: 0.0)
        for sample in UnsafeBufferPointer(start: samples, count: view.count) {
            let className: String?
            if let objcName = sample.key.class_name {
                className = String(cString: objcName)
            } else if let metadata = sample.key.swift_metadata,
                      let resolver = sample.key.swift_name_resolver {
                let resolved = resolver(metadata)
                if let data = resolved.data {
                    className = String(decoding: UnsafeRawBufferPointer(start: data, count: Int(resolved.length)), as: UTF8.self)
                } else {
                    className = nil
                }
            } else {
                className = nil
            }
            if className?.contains(name) == true {
                result.allocObjects += sample.alloc_objects
                result.allocSpace += sample.alloc_space
                result.inuseObjects += sample.inuse_objects
            }
        }
        return result
    }

    private func capture(drainingAllocations: Bool) -> dd_memory_aggregation_view_t {
        var view = dd_memory_aggregation_view_t()
        XCTAssertTrue(dd_memory_profiler_capture(drainingAllocations, &view))
        return view
    }
}

#endif
