/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import Darwin.Mach
import XCTest

import DatadogMachProfiler

final class MachSamplingProfilerTests: XCTestCase {
    private var callbackInvocations: [(traces: [stack_trace_t], userData: String?)] = []
    private let callbackTimeout: TimeInterval = 2.0

    override func setUp() {
        super.setUp()
        callbackInvocations.removeAll()
    }

    // MARK: - Callback Mechanism Tests

    func testCallback_isInvokedWithStackTraces() {
        // Given
        struct CallbackContext {
            let expectedCtx: String
            var receivedCtx: String? = nil
            var receivedTraceCount: Int = 0
        }

        let context = CCallbackContext(CallbackContext(
            expectedCtx: "callback_test_data"
        ))

        let callback: stack_trace_callback_t = { traces, count, ctx in
            CCallbackContext<CallbackContext>.withContextPointer(ctx) { context in
                context.receivedCtx = context.expectedCtx
                context.receivedTraceCount = count
            }
        }

        let mockThread = MockThread {
            // When
            let profiler = profiler_create(nil, callback, context.rawPointer)
            XCTAssertNotNil(profiler)
            XCTAssertEqual(profiler_start(profiler), 1)

            Thread.sleep(forTimeInterval: 0.002)

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")

        // Then
        XCTAssertEqual(context.value.receivedCtx, context.value.expectedCtx, "User data should be preserved")
        XCTAssertGreaterThanOrEqual(context.value.receivedTraceCount, 0, "Should receive valid trace count")

        // Cleanup
        mockThread.cancel()
    }

    // MARK: - Configuration Behavior Tests

    func testCurrentThreadOnly_limitsToSingleThread() {
        // Given
        var config = sampling_config_t(
            sampling_interval_nanos: 1_000_000,
            profile_current_thread_only: 1, // Only current thread
            max_buffer_size: 50,
            max_stack_depth: 128,
            max_thread_count: 1,
            qos_class: QOS_CLASS_DEFAULT
        )

        struct CallbackContext {
            var tids: Set<mach_port_t> = []
        }

        let context = CCallbackContext(CallbackContext())

        let callback: stack_trace_callback_t = { traces, count, ctx in
            guard count > 0, let traces else {
                return
            }

            CCallbackContext<CallbackContext>.withContextPointer(ctx) { context in
                for i in 0..<count {
                    context.tids.insert(traces[i].tid)
                }
            }
        }

        let mockThread = MockThread {
            let profiler = profiler_create(&config, callback, context.rawPointer)

            // When
            XCTAssertNotNil(profiler)
            XCTAssertEqual(profiler_start(profiler), 1)

            Thread.sleep(forTimeInterval: 0.002)

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")

        // Then
        XCTAssertEqual(context.value.tids.count, 1, "Should sample single thread when current_thread_only is enabled")

        // Cleanup
        mockThread.cancel()
    }

    func testMaxBufferSize_limitsTraceCollection() {
        // Given
        let smallBufferSize = 5
        var config = sampling_config_t(
            sampling_interval_nanos: 100_000, // Fast sampling
            profile_current_thread_only: 0,
            max_buffer_size: smallBufferSize,
            max_stack_depth: 128,
            max_thread_count: 10,
            qos_class: QOS_CLASS_DEFAULT
        )

        struct BufferCallbackContext {
            var maxReceivedCount: Int = 0
            var count: Int = 0
        }

        let context = CCallbackContext(BufferCallbackContext())

        let callback: stack_trace_callback_t = { traces, count, ctx in
            CCallbackContext<BufferCallbackContext>.withContextPointer(ctx) { context in
                context.maxReceivedCount = max(context.maxReceivedCount, count)
                context.count += count
            }
        }

        let mockThread = MockThread {
            let profiler = profiler_create(&config, callback, context.rawPointer)

            // When
            XCTAssertNotNil(profiler)
            XCTAssertEqual(profiler_start(profiler), 1)

            Thread.sleep(forTimeInterval: 0.001)

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")

        // Then
        XCTAssertGreaterThan(context.value.count, 0)
        XCTAssertLessThanOrEqual(
            context.value.maxReceivedCount,
            smallBufferSize,
            "Callback should not receive more traces than buffer size"
        )

        // Cleanup
        mockThread.cancel()
    }

    // MARK: - Thread Safety Tests

    func testConcurrentStartStop_doesNotCrash() {
        // Given
        let profiler = profiler_create(nil, { _, _, _ in }, nil)
        XCTAssertNotNil(profiler)

        let concurrentOperations = 10
        let expectation = XCTestExpectation(description: "Concurrent operations completed")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            if index % 2 == 0 {
                _ = profiler_start(profiler)
            } else {
                profiler_stop(profiler)
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)

        // Cleanup
        profiler_stop(profiler) // Ensure stopped
        profiler_destroy(profiler)
    }

    // MARK: - Error Handling Tests

    func testProfilerOperations_withInvalidProfiler_handleGracefully() {
        // Given
        let invalidProfiler: OpaquePointer? = nil

        // When & Then
        XCTAssertEqual(profiler_start(invalidProfiler), 0, "Start with invalid profiler should return failure")

        profiler_stop(invalidProfiler) // Should not crash

        XCTAssertEqual(profiler_is_running(invalidProfiler), 0, "Invalid profiler should report not running")
    }

    // MARK: - Fixed Interval Behavior Tests

    func testSampling_usesFixedInterval() {
        // Given
        let fixedInterval: UInt64 = 1_000_000 // 1ms
        var config = sampling_config_t(
            sampling_interval_nanos: fixedInterval,
            profile_current_thread_only: 1,
            max_buffer_size: 20,
            max_stack_depth: 128,
            max_thread_count: 1,
            qos_class: QOS_CLASS_DEFAULT
        )

        let contextManager = CCallbackContext([UInt64]())

        let callback: stack_trace_callback_t = { traces, count, ctx in
            guard count > 0, let traces = traces else {
                return
            }

            CCallbackContext<[UInt64]>.withContextPointer(ctx) { context in
                (0..<count).forEach { context.append(traces[$0].sampling_interval_nanos) }
            }
        }

        let mockThread = MockThread {
            let profiler = profiler_create(&config, callback, contextManager.rawPointer)

            // When
            XCTAssertNotNil(profiler)
            XCTAssertEqual(profiler_start(profiler), 1)

            // Do some work to generate samples
            for i in 0..<1_000 {
                _ = sqrt(Double(i))
                if i % 100 == 0 {
                    Thread.sleep(forTimeInterval: 0.002)
                }
            }

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")

        // Then
        XCTAssertGreaterThan(contextManager.value.count, 0, "Should receive sampling intervals")

        // All intervals should be exactly the configured fixed interval
        contextManager.value.forEach { interval in
            XCTAssertEqual(interval, fixedInterval, "Profiler should use fixed interval without jitter")
        }

        // Cleanup
        mockThread.cancel()
    }

    func testSampling_samplesAllThreads() {
        // Given
        var config = sampling_config_t(
            sampling_interval_nanos: 1_000_000, // 1ms
            profile_current_thread_only: 0, // Sample all threads
            max_buffer_size: 1,
            max_stack_depth: 128,
            max_thread_count: 0, // No limit
            qos_class: QOS_CLASS_DEFAULT
        )

        struct CallbackContext {
            var tids: Set<mach_port_t> = []
            var names: Set<String> = []
            var count: Int = 0
        }

        let context = CCallbackContext(CallbackContext())

        let callback: stack_trace_callback_t = { traces, count, ctx in
            guard count > 0, let traces else {
                return
            }

            CCallbackContext<CallbackContext>.withContextPointer(ctx) { context in
                context.count += count
                (0..<count).forEach {
                    context.tids.insert(traces[$0].tid)
                    context.names.insert(String(cString: traces[$0].thread_name))
                }
            }
        }

        // Create controlled threads using MockThreadGroup
        let threadGroup = MockThreadGroup()

        threadGroup.createThread {
            // Predictable CPU work for thread 1
            for i in 0..<1_000 {
                _ = sqrt(Double(i))
                if i % 100 == 0 {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }

        threadGroup.createThread {
            // Predictable CPU work for thread 2
            for i in 0..<1_000 {
                _ = sin(Double(i) * 0.1)
                if i % 100 == 0 {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }

        // Start profiler
        let profiler = profiler_create(&config, callback, context.rawPointer)
        XCTAssertEqual(profiler_start(profiler), 1)

        threadGroup.startAll()
        XCTAssertTrue(threadGroup.waitForAllCompletion(timeout: callbackTimeout), "All threads should complete")

        // Then
        XCTAssertGreaterThan(context.value.count, 0, "Should receive samples")
        XCTAssertGreaterThan(context.value.tids.count, 1, "Should sample multiple threads")

        // Cleanup
        profiler_stop(profiler)
        profiler_destroy(profiler)
        threadGroup.cancelAll()
    }

    // MARK: - Stack Trace Quality Tests

    func testStackTraceCapture_containsValidFramesWithBinaryImages() {
        // Given
        var config = sampling_config_t(
            sampling_interval_nanos: 2_000_000,
            profile_current_thread_only: 1,
            max_buffer_size: 10,
            max_stack_depth: 64,
            max_thread_count: 1,
            qos_class: QOS_CLASS_DEFAULT
        )

        struct CallbackContext {
            var invalidTraceFound: Bool = false
            var invalidFrameFound: Bool = false
            var invalidBinaryImageFound: Bool = false
            var count: Int = 0
        }

        let context = CCallbackContext(CallbackContext())

        let callback: stack_trace_callback_t = { traces, count, ctx in
            guard count > 0, let traces else {
                return
            }

            CCallbackContext<CallbackContext>.withContextPointer(ctx) { context in
                context.count += count

                (0..<count).forEach {
                    let trace = traces[$0]
                    // Validate trace
                    context.invalidTraceFound = trace.tid == 0 || // invalid thread ID
                        trace.timestamp == 0 || // invalid timestamp
                        trace.sampling_interval_nanos != 2_000_000 ||
                        trace.frame_count > 64 // exceed stack depth

                    if trace.frame_count > 0 && trace.frames != nil {
                        let frames = UnsafeBufferPointer(start: trace.frames, count: Int(trace.frame_count))

                        for frame in frames {
                            // Valid frame should have non-zero instruction pointer
                            context.invalidFrameFound = frame.instruction_ptr == 0

                            let image = frame.image

                            // Validate binary image fields
                            context.invalidBinaryImageFound = image.load_address == 0 || // Should have valid load address
                                image.filename == nil || // Should have filename
                                strlen(image.filename) == 0 // Filename should not be empty
                        }
                    }
                }
            }
        }
        let mockThread = MockThread {
            let profiler = profiler_create(&config, callback, context.rawPointer)

            // When
            XCTAssertEqual(profiler_start(profiler), 1)

            // Create some stack depth
            recursiveFunction(depth: 5) {
                _ = sin(Double.random(in: 0...Double.pi))
                Thread.sleep(forTimeInterval: 0.001)
            }

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")

        // Then
        XCTAssertGreaterThan(context.value.count, 0, "Should receive samples")
        XCTAssertFalse(context.value.invalidTraceFound, "Should receive valid stack traces")
        XCTAssertFalse(context.value.invalidFrameFound, "Should capture valid stack frames with non-zero instruction pointers")
        XCTAssertFalse(context.value.invalidBinaryImageFound, "Should capture valid binary image information")

        // Cleanup
        mockThread.cancel()
    }

    func testStackTraceCapture_respectsMaxDepthLimit() {
        // Given
        let maxDepth: UInt32 = 10
        var config = sampling_config_t(
            sampling_interval_nanos: 2_000_000,
            profile_current_thread_only: 1,
            max_buffer_size: 1,
            max_stack_depth: maxDepth,
            max_thread_count: 1,
            qos_class: QOS_CLASS_DEFAULT
        )

        struct CallbackContext {
            var maxFrameCount: UInt32 = 0
        }

        let context = CCallbackContext(CallbackContext())

        let callback: stack_trace_callback_t = { traces, count, ctx in
            guard count > 0, let traces else {
                return
            }

            CCallbackContext<CallbackContext>.withContextPointer(ctx) { context in
                context.maxFrameCount = (0..<count).reduce(context.maxFrameCount) {
                    max($0, traces[$1].frame_count)
                }
            }
        }

        let mockThread = MockThread {
            let profiler = profiler_create(&config, callback, context.rawPointer)

            // When
            XCTAssertEqual(profiler_start(profiler), 1)
            // Create deep stack
            recursiveFunction(depth: 20) { // Deeper than max_depth
                Thread.sleep(forTimeInterval: 0.001)
            }

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout), "MockThread work should complete")

        // Then
        XCTAssertGreaterThan(context.value.maxFrameCount, 0)
        XCTAssertLessThanOrEqual(context.value.maxFrameCount, maxDepth, "Frame count should not exceed configured max depth")

        // Cleanup
        mockThread.cancel()
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
