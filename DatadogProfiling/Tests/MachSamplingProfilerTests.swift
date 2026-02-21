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

final class MachSamplingProfilerTests: XCTestCase {
    private let callbackTimeout: TimeInterval = 2.0

    override func tearDown() {
        dd_profiler_stop()
        dd_profiler_destroy()
        super.tearDown()
    }

    // MARK: - Sampling & profile aggregation

    func testGlobalProfiler_collectsSamplesUnderCPULoad() {
        let mockThread = MockThread {
            XCTAssertEqual(dd_profiler_start(), 1)

            for i in 0..<5_000 {
                _ = sqrt(Double(i))
                if i % 500 == 0 {
                    Thread.sleep(forTimeInterval: 0.002)
                }
            }

            dd_profiler_stop()

            let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
            XCTAssertGreaterThan(sampleCount, 0, "Profiler should collect samples while the workload runs")

            dd_profiler_destroy()
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")
        mockThread.cancel()
    }

    func testSampling_samplesAllThreads_withDefaultConfig() {
        let threadGroup = MockThreadGroup()

        threadGroup.createThread {
            for i in 0..<1_000 {
                _ = sqrt(Double(i))
                if i % 100 == 0 {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }

        threadGroup.createThread {
            for i in 0..<1_000 {
                _ = sin(Double(i) * 0.1)
                if i % 100 == 0 {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }

        XCTAssertEqual(dd_profiler_start(), 1)

        threadGroup.startAll()
        XCTAssertTrue(threadGroup.waitForAllCompletion(timeout: callbackTimeout), "All threads should complete")

        dd_profiler_stop()

        let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
        XCTAssertGreaterThan(sampleCount, 0, "Default config profiles all threads; expect samples while worker threads run")

        dd_profiler_destroy()
        threadGroup.cancelAll()
    }

    func testDeepStackWorkload_stillProducesSamples() {
        let mockThread = MockThread {
            XCTAssertEqual(dd_profiler_start(), 1)

            recursiveFunction(depth: 20) {
                Thread.sleep(forTimeInterval: 0.002)
            }

            dd_profiler_stop()

            let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
            XCTAssertGreaterThan(sampleCount, 0, "Deep stacks should still yield profile samples")

            dd_profiler_destroy()
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")
        mockThread.cancel()
    }

    // MARK: - Thread safety

    func testConcurrentStartStop_doesNotCrash() {
        let concurrentOperations = 10
        let expectation = XCTestExpectation(description: "Concurrent operations completed")
        expectation.expectedFulfillmentCount = concurrentOperations

        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            if index % 2 == 0 {
                _ = dd_profiler_start()
            } else {
                dd_profiler_stop()
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.1)

        dd_profiler_stop()
        dd_profiler_destroy()
    }
}

// MARK: - Helper Methods

private func recursiveFunction(depth: Int, completion: @escaping () -> Void) {
    if depth <= 0 {
        completion()
    } else {
        recursiveFunction(depth: depth - 1, completion: completion)
    }
}
#endif // !os(watchOS)
