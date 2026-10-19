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

    func testSharedCacheMatchesOwnedLookupAndReusesFilenameStorage() throws {
        let cache = try XCTUnwrap(binary_image_cache_shared_for_testing())
        XCTAssertEqual(cache, binary_image_cache_shared_for_testing())
        let symbol = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc"))
        let address = UInt64(UInt(bitPattern: symbol))
        var owned = binary_image_t()
        defer { binary_image_destroy(&owned) }
        XCTAssertTrue(binary_image_lookup_pc(&owned, symbol))

        var cached = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_for_testing(cache, address, &cached))
        XCTAssertEqual(cached.load_address, owned.load_address)
        XCTAssertEqual(UUID(uuid: cached.uuid), UUID(uuid: owned.uuid))
        XCTAssertEqual(String(cString: try XCTUnwrap(cached.filename)), String(cString: try XCTUnwrap(owned.filename)))

        var repeated = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_for_testing(cache, address, &repeated))
        XCTAssertEqual(repeated.filename, cached.filename)
    }

    func testSharedCacheRejectsInvalidAddressAndResetsOutput() throws {
        let cache = try XCTUnwrap(binary_image_cache_shared_for_testing())
        var image = binary_image_t(load_address: 0xABCD, uuid: UUID().uuid, filename: nil)

        XCTAssertFalse(binary_image_cache_lookup_for_testing(cache, 1, &image))

        XCTAssertEqual(image.load_address, 0)
        XCTAssertNil(image.filename)
        XCTAssertTrue(isZero(uuid: image.uuid))
    }

    func testCacheMissResolvesAndRetainsOwnedMetadata() throws {
        let cache = try XCTUnwrap(binary_image_cache_create_for_testing())
        defer { binary_image_cache_destroy_for_testing(cache) }
        XCTAssertEqual(binary_image_cache_size_for_testing(cache), 0)
        let symbol = try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc"))
        let address = UInt64(UInt(bitPattern: symbol))
        var owned = binary_image_t()
        defer { binary_image_destroy(&owned) }
        XCTAssertTrue(binary_image_lookup_pc(&owned, symbol))

        var cached = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_for_testing(cache, address, &cached))
        XCTAssertEqual(cached.load_address, owned.load_address)
        XCTAssertEqual(UUID(uuid: cached.uuid), UUID(uuid: owned.uuid))
        XCTAssertEqual(String(cString: try XCTUnwrap(cached.filename)), String(cString: try XCTUnwrap(owned.filename)))
        XCTAssertEqual(binary_image_cache_size_for_testing(cache), 1)

        var repeated = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_for_testing(cache, address, &repeated))
        XCTAssertEqual(repeated.filename, cached.filename)
        XCTAssertEqual(binary_image_cache_size_for_testing(cache), 1)
    }

    func testDuplicateNotificationAndUUIDOnlyChangeReuseFilenameStorage() throws {
        let cache = try XCTUnwrap(binary_image_cache_create_for_testing())
        defer { binary_image_cache_destroy_for_testing(cache) }
        let fixture = BinaryImageFixture(identity: 1)
        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libSame")
        var first = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &first))

        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libSame")
        var duplicate = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &duplicate))
        XCTAssertEqual(duplicate.filename, first.filename)

        fixture.updateIdentity(2)
        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libSame")
        var updated = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &updated))
        XCTAssertEqual(updated.uuid.0, 2)
        XCTAssertEqual(updated.filename, first.filename)
        XCTAssertEqual(binary_image_cache_size_for_testing(cache), 1)
    }

    func testReplacementAtReusedImageAddressPreservesBorrowedNames() throws {
        let cache = try XCTUnwrap(binary_image_cache_create_for_testing())
        defer { binary_image_cache_destroy_for_testing(cache) }
        let fixture = BinaryImageFixture(identity: 1)
        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libFirst")
        var first = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &first))

        fixture.updateIdentity(2)
        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libSecond")
        var second = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &second))

        XCTAssertEqual(second.uuid.0, 2)
        XCTAssertEqual(String(cString: try XCTUnwrap(second.filename)), "libSecond")
        XCTAssertEqual(first.uuid.0, 1)
        XCTAssertEqual(String(cString: try XCTUnwrap(first.filename)), "libFirst")
        XCTAssertEqual(binary_image_cache_size_for_testing(cache), 1)
    }

    func testReplacementWithFilenameAllocationFailureRefreshesMetadataAndPreservesBorrowedNames() throws {
        let cache = try XCTUnwrap(binary_image_cache_create_for_testing())
        defer { binary_image_cache_destroy_for_testing(cache) }
        let fixture = BinaryImageFixture(identity: 1)
        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libFirst")
        var first = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &first))

        fixture.updateIdentity(2)
        binary_image_cache_fail_next_filename_allocation_for_testing(cache)
        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libSecond")
        var replacement = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &replacement))
        XCTAssertEqual(replacement.load_address, UInt64(fixture.address))
        XCTAssertEqual(replacement.uuid.0, 2)
        XCTAssertNil(replacement.filename)
        XCTAssertEqual(String(cString: try XCTUnwrap(first.filename)), "libFirst")

        binary_image_cache_add_image_for_testing(cache, fixture.storage, "libSecond")
        var retried = binary_image_t()
        XCTAssertTrue(binary_image_cache_lookup_image_for_testing(cache, fixture.address, &retried))
        XCTAssertEqual(retried.uuid.0, 2)
        XCTAssertEqual(String(cString: try XCTUnwrap(retried.filename)), "libSecond")
        XCTAssertEqual(String(cString: try XCTUnwrap(first.filename)), "libFirst")
        XCTAssertEqual(binary_image_cache_size_for_testing(cache), 1)
    }

    func testConcurrentImageUpdatesAndBorrowedReaders() throws {
        let handle = BinaryImageCacheHandle(cache: try XCTUnwrap(binary_image_cache_create_for_testing()))
        defer { binary_image_cache_destroy_for_testing(handle.cache) }
        let fixture = BinaryImageFixture(identity: 1)
        binary_image_cache_add_image_for_testing(handle.cache, fixture.storage, "libFirst")
        let counts = BinaryImageStressCounts()

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            if worker == 0 {
                for iteration in 0..<2_000 {
                    fixture.updateIdentity(UInt8(iteration % 2 + 1))
                    binary_image_cache_add_image_for_testing(
                        handle.cache, fixture.storage, iteration.isMultiple(of: 2) ? "libFirst" : "libSecond"
                    )
                }
            } else {
                var failures = 0
                for _ in 0..<4_000 {
                    var image = binary_image_t()
                    guard binary_image_cache_lookup_image_for_testing(handle.cache, fixture.address, &image),
                          let filename = image.filename else {
                        failures += 1
                        continue
                    }
                    let name = String(cString: filename)
                    if (image.uuid.0 != 1 || name != "libFirst") && (image.uuid.0 != 2 || name != "libSecond") {
                        failures += 1
                    }
                }
                counts.record(failures: failures)
            }
        }

        XCTAssertEqual(counts.snapshot(), 0)
        XCTAssertEqual(binary_image_cache_size_for_testing(handle.cache), 1)
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

private final class BinaryImageFixture: @unchecked Sendable {
    let storage: UnsafeMutableRawPointer

    var address: UInt { UInt(bitPattern: storage) }

    init(identity: UInt8) {
        storage = .allocate(
            byteCount: MemoryLayout<mach_header_64>.size + MemoryLayout<uuid_command>.size,
            alignment: MemoryLayout<mach_header_64>.alignment
        )
        var header = mach_header_64()
        header.magic = MH_MAGIC_64
        header.ncmds = 1
        header.sizeofcmds = UInt32(MemoryLayout<uuid_command>.size)
        storage.storeBytes(of: header, as: mach_header_64.self)
        updateIdentity(identity)
    }

    deinit {
        storage.deallocate()
    }

    func updateIdentity(_ identity: UInt8) {
        var command = uuid_command()
        command.cmd = UInt32(LC_UUID)
        command.cmdsize = UInt32(MemoryLayout<uuid_command>.size)
        command.uuid = (identity, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        storage.advanced(by: MemoryLayout<mach_header_64>.size).storeBytes(of: command, as: uuid_command.self)
    }
}

private struct BinaryImageCacheHandle: @unchecked Sendable {
    let cache: OpaquePointer
}

private final class BinaryImageStressCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = 0

    func record(failures: Int) {
        lock.lock()
        self.failures += failures
        lock.unlock()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }
}

#endif // !os(watchOS)
