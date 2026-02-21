/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest
import DatadogInternal

// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
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
        let callbackTimeout: TimeInterval = 2.0

        let mockThread = MockThread {
            XCTAssertEqual(dd_profiler_start(), 1)

            self.recursiveResolverWork(depth: 5) {
                _ = sin(Double.random(in: 0...Double.pi))
                Thread.sleep(forTimeInterval: 0.001)
            }

            dd_profiler_stop()

            let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
            XCTAssertGreaterThan(sampleCount, 0, "Global profiler should have collected at least one resolved sample")

            dd_profiler_destroy()
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: callbackTimeout))

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
