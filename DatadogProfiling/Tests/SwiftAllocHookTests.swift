/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest
import DatadogMachProfiler

private final class PureSwiftAllocationFixture {
    var payload = (1, 2, 3, 4)
}

private final class NSObjectAllocationFixture: NSObject {
    var payload = (1, 2, 3, 4)
}

private enum SwiftAllocationRecorder {
    struct Allocation {
        let address: UInt
        let size: UInt64
        let name: String?
    }

    static let lock = NSLock()
    nonisolated(unsafe) static var targetMetadata: UInt = 0
    nonisolated(unsafe) static var allocations: [Allocation] = []
    nonisolated(unsafe) static var observedAddresses: Set<UInt> = []
    nonisolated(unsafe) static var deallocationAddresses: Set<UInt> = []
    nonisolated(unsafe) static var matchedDeallocations = 0

    static func reset(for type: AnyClass) {
        lock.lock()
        targetMetadata = UInt(bitPattern: unsafeBitCast(type, to: UnsafeRawPointer.self))
        allocations.removeAll()
        observedAddresses.removeAll()
        deallocationAddresses.removeAll()
        matchedDeallocations = 0
        lock.unlock()
    }

    static func recordAllocation(
        address: UnsafeRawPointer?,
        size: UInt64,
        metadata: OpaquePointer?,
        resolveName: dd_swift_class_name_resolver_t?
    ) {
        guard let address, let metadata else {
            return
        }
        lock.lock()
        let matches = UInt(bitPattern: metadata) == targetMetadata
        lock.unlock()
        guard matches else {
            return
        }

        let resolved = resolveName?(metadata)
        let name: String?
        if let bytes = resolved?.data, let length = resolved?.length, length > 0 {
            name = String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(length)), as: UTF8.self)
        } else {
            name = nil
        }
        lock.lock()
        let value = UInt(bitPattern: address)
        allocations.append(Allocation(address: value, size: size, name: name))
        observedAddresses.insert(value)
        lock.unlock()
    }

    static func recordDeallocation(address: UnsafeRawPointer?) {
        guard let address else {
            return
        }
        let value = UInt(bitPattern: address)
        lock.lock()
        if observedAddresses.remove(value) != nil {
            deallocationAddresses.insert(value)
            matchedDeallocations += 1
        }
        lock.unlock()
    }

    static func snapshot() -> (
        allocations: [Allocation], deallocations: Set<UInt>, matchedDeallocations: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (allocations, deallocationAddresses, matchedDeallocations)
    }
}

private func observeSwiftAllocation(
    _ address: UnsafeRawPointer?,
    _ size: UInt64,
    _ metadata: OpaquePointer?,
    _ resolveName: dd_swift_class_name_resolver_t?
) {
    SwiftAllocationRecorder.recordAllocation(
        address: address, size: size, metadata: metadata, resolveName: resolveName
    )
}

private func observeSwiftDeallocation(_ address: UnsafeRawPointer?) {
    SwiftAllocationRecorder.recordDeallocation(address: address)
}

final class SwiftAllocHookTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let status = dd_swift_alloc_hook_start(observeSwiftAllocation, observeSwiftDeallocation)
        XCTAssertTrue(
            status == DD_SWIFT_ALLOC_HOOK_OK ||
            status == DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED,
            "Swift rebinding must install, got \(status)"
        )
    }

    override func tearDown() {
        dd_swift_alloc_hook_stop()
        super.tearDown()
    }

    func testInstallPatchesRequiredSlots() {
        let diagnostics = dd_swift_alloc_hook_diagnostics()
        XCTAssertTrue(diagnostics.is_enabled)
        XCTAssertGreaterThan(diagnostics.alloc_slots_patched, 0)
        XCTAssertGreaterThan(diagnostics.class_dealloc_slots_patched, 0)
        XCTAssertEqual(diagnostics.conflicting_slots, 0)
        XCTAssertEqual(diagnostics.failed_slot_writes, 0)
    }

    func testPureSwiftClassIsObservedWithNameAndSize() throws {
        SwiftAllocationRecorder.reset(for: PureSwiftAllocationFixture.self)
        let object = PureSwiftAllocationFixture()
        object.payload.0 = 42
        let address = UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())

        try withExtendedLifetime(object) {
            let matches = SwiftAllocationRecorder.snapshot().allocations
                .filter { $0.address == address }
            let match = try XCTUnwrap(matches.first)
            XCTAssertEqual(matches.count, 1)
            XCTAssertGreaterThan(match.size, 0)
            XCTAssertTrue(match.name?.contains("PureSwiftAllocationFixture") == true)
        }
    }

    func testNSObjectSubclassDoesNotTakeSwiftPath() {
        SwiftAllocationRecorder.reset(for: NSObjectAllocationFixture.self)
        let object = NSObjectAllocationFixture()
        object.payload.0 = 42
        let address = UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())

        withExtendedLifetime(object) {
            XCTAssertFalse(
                SwiftAllocationRecorder.snapshot().allocations.contains { $0.address == address }
            )
        }
    }

    func testClassDeallocationNotifiesTheObservedAddress() {
        SwiftAllocationRecorder.reset(for: PureSwiftAllocationFixture.self)
        let address = makeAndReleasePureSwiftFixture()

        let snapshot = SwiftAllocationRecorder.snapshot()
        XCTAssertTrue(snapshot.allocations.contains { $0.address == address })
        XCTAssertTrue(snapshot.deallocations.contains(address))
    }

    func testStopAndRestartKeepForwardingWithoutDuplicateObservation() {
        SwiftAllocationRecorder.reset(for: PureSwiftAllocationFixture.self)
        dd_swift_alloc_hook_stop()
        let stoppedObject = PureSwiftAllocationFixture()
        withExtendedLifetime(stoppedObject) {
            XCTAssertTrue(SwiftAllocationRecorder.snapshot().allocations.isEmpty)
        }

        DrainObserver.resetAllocation(for: PureSwiftAllocationFixture.self)
        XCTAssertEqual(
            dd_swift_alloc_hook_start(
                { _, _, metadata, _ in DrainObserver.observeAllocation(metadata) },
                observeSwiftDeallocation
            ),
            DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED
        )
        let allocationFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let object = PureSwiftAllocationFixture()
            withExtendedLifetime(object) {}
            allocationFinished.signal()
        }
        let entered = DrainObserver.allocationEntered.wait(timeout: .now() + 5)
        guard entered == .success else {
            DrainObserver.allocationRelease.signal()
            XCTFail("allocation observer was not entered")
            return
        }

        let stopFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            dd_swift_alloc_hook_stop()
            stopFinished.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while dd_swift_alloc_hook_diagnostics().is_enabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertFalse(dd_swift_alloc_hook_diagnostics().is_enabled)
        XCTAssertEqual(stopFinished.wait(timeout: .now() + .milliseconds(100)), .timedOut)

        let restartFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = dd_swift_alloc_hook_start(observeSwiftAllocation, observeSwiftDeallocation)
            restartFinished.signal()
        }
        XCTAssertEqual(restartFinished.wait(timeout: .now() + .milliseconds(100)), .timedOut)

        DrainObserver.allocationRelease.signal()
        XCTAssertEqual(stopFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(restartFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(allocationFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(DrainObserver.allocationCount(), 1)
        XCTAssertTrue(SwiftAllocationRecorder.snapshot().allocations.isEmpty)

        let resumedObject = PureSwiftAllocationFixture()
        let address = UInt(bitPattern: Unmanaged.passUnretained(resumedObject).toOpaque())
        withExtendedLifetime(resumedObject) {
            XCTAssertEqual(
                SwiftAllocationRecorder.snapshot().allocations
                    .filter { $0.address == address }.count,
                1
            )
        }
    }

    func testMissingObserverFailsClosed() {
        dd_swift_alloc_hook_stop()
        XCTAssertEqual(
            dd_swift_alloc_hook_start(nil, observeSwiftDeallocation),
            DD_SWIFT_ALLOC_HOOK_FAILED_INVALID_OBSERVER
        )
        XCTAssertFalse(dd_swift_alloc_hook_diagnostics().is_enabled)
    }

    func testConcurrentPureSwiftAllocationAndRelease() {
        SwiftAllocationRecorder.reset(for: PureSwiftAllocationFixture.self)
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            var objects: [PureSwiftAllocationFixture] = []
            for _ in 0..<1_000 {
                objects.append(PureSwiftAllocationFixture())
            }
            withExtendedLifetime(objects) {}
            objects.removeAll()
        }

        let snapshot = SwiftAllocationRecorder.snapshot()
        XCTAssertEqual(snapshot.allocations.count, 4_000)
        XCTAssertEqual(snapshot.matchedDeallocations, 4_000)
    }

    func testStopDrainsDeallocationCallback() {
        dd_swift_alloc_hook_stop()
        var object: PureSwiftAllocationFixture? = PureSwiftAllocationFixture()
        let address = UInt(bitPattern: Unmanaged.passRetained(object!).toOpaque())
        object = nil
        DrainObserver.resetDeallocation(address: address)
        XCTAssertEqual(
            dd_swift_alloc_hook_start(
                observeSwiftAllocation,
                { address in DrainObserver.observeDeallocation(address) }
            ),
            DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED
        )

        let deallocationFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            Unmanaged<PureSwiftAllocationFixture>
                .fromOpaque(UnsafeRawPointer(bitPattern: address)!)
                .release()
            deallocationFinished.signal()
        }
        let entered = DrainObserver.deallocationEntered.wait(timeout: .now() + 5)
        guard entered == .success else {
            DrainObserver.deallocationRelease.signal()
            XCTFail("deallocation observer was not entered")
            return
        }

        let stopFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            dd_swift_alloc_hook_stop()
            stopFinished.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while dd_swift_alloc_hook_diagnostics().is_enabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertFalse(dd_swift_alloc_hook_diagnostics().is_enabled)
        XCTAssertEqual(stopFinished.wait(timeout: .now() + .milliseconds(100)), .timedOut)

        DrainObserver.deallocationRelease.signal()
        XCTAssertEqual(stopFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(deallocationFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(DrainObserver.deallocationCount(), 1)
    }

    @inline(never)
    private func makeAndReleasePureSwiftFixture() -> UInt {
        let object = PureSwiftAllocationFixture()
        object.payload.0 = 42
        return UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
    }

    private enum DrainObserver {
        static let allocationEntered = DispatchSemaphore(value: 0)
        static let allocationRelease = DispatchSemaphore(value: 0)
        static let deallocationEntered = DispatchSemaphore(value: 0)
        static let deallocationRelease = DispatchSemaphore(value: 0)
        static let lock = NSLock()
        nonisolated(unsafe) static var targetMetadata: UInt = 0
        nonisolated(unsafe) static var targetAddress: UInt = 0
        nonisolated(unsafe) static var allocations = 0
        nonisolated(unsafe) static var deallocations = 0

        static func resetAllocation(for type: AnyClass) {
            lock.lock()
            targetMetadata = UInt(bitPattern: unsafeBitCast(type, to: UnsafeRawPointer.self))
            allocations = 0
            lock.unlock()
        }

        static func observeAllocation(_ metadata: OpaquePointer?) {
            guard let metadata else {
                return
            }
            lock.lock()
            let matches = UInt(bitPattern: metadata) == targetMetadata
            lock.unlock()
            guard matches else {
                return
            }
            allocationEntered.signal()
            _ = allocationRelease.wait(timeout: .now() + 10)
            lock.lock()
            allocations += 1
            lock.unlock()
        }

        static func allocationCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return allocations
        }

        static func resetDeallocation(address: UInt) {
            lock.lock()
            targetAddress = address
            deallocations = 0
            lock.unlock()
        }

        static func observeDeallocation(_ address: UnsafeRawPointer?) {
            guard let address else {
                return
            }
            lock.lock()
            let matches = UInt(bitPattern: address) == targetAddress
            lock.unlock()
            guard matches else {
                return
            }
            deallocationEntered.signal()
            _ = deallocationRelease.wait(timeout: .now() + 10)
            lock.lock()
            deallocations += 1
            lock.unlock()
        }

        static func deallocationCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return deallocations
        }
    }
}
#endif
