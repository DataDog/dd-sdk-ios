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
import DatadogMachProfiler.Cxx
// swiftlint:enable duplicate_imports

final class BinaryImageResolverTests: XCTestCase {
    func testBinaryImageInit_setsFieldsToDefaults() {
        // Given
        var image = binary_image_t(load_address: 0xABCD, uuid: UUID().uuid, filename: nil)

        // When
        let result = binary_image_init(&image)

        // Then
        XCTAssertTrue(result, "binary_image_init should return true for a valid pointer")
        XCTAssertEqual(image.load_address, 0)
        XCTAssertNil(image.filename)

        XCTAssertTrue(isZero(uuid: image.uuid))
    }

    func testBinaryImageDestroy_freesFilenameAndResetsFields() {
        // Given
        var image = binary_image_t(load_address: 0, uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), filename: nil)
        binary_image_init(&image)

        // Simulate a resolved image with an allocated filename
        let testName = "TestBinary"
        guard let fname = strdup(testName) else {
            XCTFail("Failed to allocate test filename")
            return
        }
        image.filename = UnsafePointer(fname)
        image.load_address = 0x100000000

        // When
        binary_image_destroy(&image)

        // Then
        XCTAssertNil(image.filename, "filename should be nil after destroy")
        XCTAssertEqual(image.load_address, 0, "load_address should be zeroed after destroy")
    }

    func testBinaryImageLookupPC_withValidAddress() {
        // Given
        var image = binary_image_t(load_address: 0, uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), filename: nil)
        binary_image_init(&image)

        guard let validPC = anyKnownProgramCounter() else {
            XCTFail("Could not find a valid PC for testing")
            return
        }

        // When
        let result = binary_image_lookup_pc(&image, validPC)

        // Then
        XCTAssertTrue(result)
        XCTAssertGreaterThan(image.load_address, 0)
        if let filename = image.filename {
            XCTAssertGreaterThan(strlen(filename), 0)
        }

        XCTAssertFalse(isZero(uuid: image.uuid), "UUID should not be all zeros for a valid image")

        // Cleanup
        binary_image_destroy(&image)
    }

    func testBinaryImageLookupPC_withInvalidAddress() {
        // Given
        var image = binary_image_t(load_address: 0, uuid: UUID().uuid, filename: nil)
        binary_image_init(&image)

        // 0x1 is below MIN_USERSPACE_ADDR and should be rejected immediately.
        let invalidPC = UnsafeMutableRawPointer(bitPattern: 0x1)

        // When
        let result = binary_image_lookup_pc(&image, invalidPC)

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(image.load_address, 0)
        XCTAssertNil(image.filename)
        XCTAssertTrue(isZero(uuid: image.uuid))
    }

    func testSamplingProfilerWithResolver_producesValidBinaryImages() {
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
            var unresolvedFrameFound: Bool = false
            var resolvedFrameCount: Int = 0
            var sampleCount: Int = 0
        }

        let context = CCallbackContext(CallbackContext())

        // The callback resolves binary images in-place, then validates the resolved data.
        let callback: stack_trace_callback_t = { traces, count, ctx in
            guard count > 0, let traces else {
                return
            }

            // Resolve binary images for all frames using the slow path (no cache)
            for i in 0..<count {
                for j in 0..<Int(traces[i].frame_count) {
                    binary_image_init(&traces[i].frames[j].image)
                    binary_image_lookup_pc(&traces[i].frames[j].image, UnsafeMutableRawPointer(bitPattern: UInt(traces[i].frames[j].instruction_ptr)))
                }
            }

            CCallbackContext<CallbackContext>.withContextPointer(ctx) { context in
                context.sampleCount += count

                for i in 0..<count {
                    guard traces[i].frame_count > 0, let frames = traces[i].frames else { continue }

                    let buffer = UnsafeBufferPointer(start: frames, count: Int(traces[i].frame_count))
                    for frame in buffer {
                        let image = frame.image
                        // A resolved frame should have a valid load address.
                        if image.load_address == 0 {
                            context.unresolvedFrameFound = true
                        }
                        if let filename = image.filename {
                            XCTAssertGreaterThan(strlen(filename), 0)
                        }
                        context.resolvedFrameCount += 1
                    }
                }
            }

            // Cleanup allocated image data
            for i in 0..<count {
                for j in 0..<Int(traces[i].frame_count) {
                    binary_image_destroy(&traces[i].frames[j].image)
                }
            }
        }

        let callbackTimeout: TimeInterval = 2.0

        let mockThread = MockThread {
            let profiler = profiler_create(&config, callback, context.rawPointer)

            XCTAssertEqual(profiler_start(profiler), 1)

            // Generate some stack depth to be sampled
            self.recursiveResolverWork(depth: 5) {
                _ = sin(Double.random(in: 0...Double.pi))
                Thread.sleep(forTimeInterval: 0.001)
            }

            profiler_stop(profiler)
            profiler_destroy(profiler)
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout))

        // Then
        XCTAssertGreaterThan(context.value.sampleCount, 0)
        XCTAssertGreaterThan(context.value.resolvedFrameCount, 0)
        XCTAssertFalse(context.value.unresolvedFrameFound)

        mockThread.cancel()
    }

    private func anyKnownProgramCounter() -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            return nil
        }

        let symbols = [
            "strlen",
            "malloc",
            "free",
            "dlopen",
            "dlsym"
        ]
        guard let randomSymbol = symbols.randomElement() else {
            return nil
        }
        return randomSymbol.withCString { dlsym(handle, $0) }
    }

    private func isZero(uuid: uuid_t) -> Bool {
        let zeroUUID = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        return withUnsafeBytes(of: uuid) { imageBytes in
            withUnsafeBytes(of: zeroUUID) { zeroBytes in
                imageBytes.elementsEqual(zeroBytes)
            }
        }
    }

    private func recursiveResolverWork(depth: Int, completion: @escaping () -> Void) {
        if depth <= 0 {
            completion()
        } else {
            recursiveResolverWork(depth: depth - 1, completion: completion)
        }
    }
}

#endif // !os(watchOS)
