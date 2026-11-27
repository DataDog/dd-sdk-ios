/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import Foundation
import MachO
import XCTest
import DatadogMachProfiler.Testing

final class FishhookTests: XCTestCase {
    func testKnownConflictDoesNotGrantWriteAccess() throws {
        let section = try FishhookSection()
        section.select(section.middleSlot)
        for page in 0..<3 {
            XCTAssertEqual(section.protectPage(page, protection: VM_PROT_READ), KERN_SUCCESS)
        }
        let state = RebindingState()
        state.firstTarget = FishhookTarget.competing
        let probe = ProtectionProbe()

        section.rebind(state, probe: probe)

        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(section.slots[section.middleSlot], FishhookTarget.original)
        XCTAssertEqual(state.firstTarget, FishhookTarget.competing)
        XCTAssertEqual(state.conflicts, 1)
        XCTAssertEqual(state.patched, 0)
        XCTAssertEqual(state.failed, 0)
        for page in 0..<3 {
            XCTAssertEqual(section.pageProtection(page), VM_PROT_READ)
        }
    }

    func testSuccessfulRebindingPreservesNeighboringPageProtections() throws {
        let readWrite = VM_PROT_READ | VM_PROT_WRITE
        let protections = [
            [VM_PROT_READ, VM_PROT_READ, VM_PROT_READ],
            [VM_PROT_READ, VM_PROT_READ, readWrite],
            [readWrite, readWrite, VM_PROT_READ]
        ]
        for pages in protections {
            let slotsPerPage = getpagesize() / Int32(MemoryLayout<UnsafeMutableRawPointer?>.stride)
            for targetSlot in [Int(slotsPerPage), 2 * Int(slotsPerPage) - 1] {
                let section = try FishhookSection()
                section.select(targetSlot)
                for page in 0..<3 {
                    XCTAssertEqual(section.protectPage(page, protection: pages[page]), KERN_SUCCESS)
                }
                let state = RebindingState()
                let probe = ProtectionProbe()

                section.rebind(state, probe: probe)

                XCTAssertEqual(probe.calls, 1)
                XCTAssertEqual(section.slots[targetSlot], FishhookTarget.replacement)
                XCTAssertEqual(state.firstTarget, FishhookTarget.original)
                XCTAssertEqual(state.patched, 1)
                XCTAssertEqual(state.conflicts, 0)
                XCTAssertEqual(state.failed, 0)
                XCTAssertEqual(section.pageProtection(0), pages[0])
                XCTAssertEqual(section.pageProtection(1), readWrite)
                XCTAssertEqual(section.pageProtection(2), pages[2])
            }
        }
    }

    func testFailedGrantLeavesSlotAndFirstTargetUnchanged() throws {
        let section = try FishhookSection()
        section.select(section.middleSlot)
        XCTAssertEqual(section.protectPage(1, protection: VM_PROT_READ), KERN_SUCCESS)
        let state = RebindingState()
        let probe = ProtectionProbe(fails: true)

        section.rebind(state, probe: probe)

        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(section.slots[section.middleSlot], FishhookTarget.original)
        XCTAssertNil(state.firstTarget)
        XCTAssertEqual(state.patched, 0)
        XCTAssertEqual(state.conflicts, 0)
        XCTAssertEqual(state.failed, 1)
        XCTAssertEqual(section.pageProtection(1), VM_PROT_READ)
    }

    func testCompetingPublicationDuringGrantIsRejected() throws {
        let section = try FishhookSection()
        section.select(section.middleSlot)
        XCTAssertEqual(section.protectPage(1, protection: VM_PROT_READ), KERN_SUCCESS)
        let state = RebindingState()
        let probe = ProtectionProbe(
            publishTarget: state.firstTargetStorage, publication: FishhookTarget.competing
        )

        section.rebind(state, probe: probe)

        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(section.slots[section.middleSlot], FishhookTarget.original)
        XCTAssertEqual(state.firstTarget, FishhookTarget.competing)
        XCTAssertEqual(state.conflicts, 1)
        XCTAssertEqual(state.patched, 0)
        XCTAssertEqual(state.failed, 0)
        XCTAssertEqual(section.pageProtection(1), VM_PROT_READ | VM_PROT_WRITE)
    }

    func testConcurrentFirstPublicationKeepsOneForwardingTarget() throws {
        let first = try FishhookSection()
        let second = try FishhookSection()
        let probe = ProtectionProbe()
        for _ in 0..<100 {
            first.select(first.middleSlot, target: FishhookTarget.original)
            second.select(second.middleSlot, target: FishhookTarget.competing)
            let state = RebindingState()
            let group = DispatchGroup()
            let start = DispatchSemaphore(value: 0)
            let queue = DispatchQueue.global()
            group.enter()
            queue.async {
                start.wait()
                first.rebind(state, probe: probe)
                group.leave()
            }
            group.enter()
            queue.async {
                start.wait()
                second.rebind(state, probe: probe)
                group.leave()
            }
            start.signal()
            start.signal()
            group.wait()

            XCTAssertEqual(state.patched, 1)
            XCTAssertEqual(state.conflicts, 1)
            XCTAssertEqual(state.failed, 0)
            XCTAssertTrue(state.firstTarget == FishhookTarget.original || state.firstTarget == FishhookTarget.competing)
            XCTAssertEqual(
                first.slots[first.middleSlot],
                state.firstTarget == FishhookTarget.original ? FishhookTarget.replacement : FishhookTarget.original
            )
            XCTAssertEqual(
                second.slots[second.middleSlot],
                state.firstTarget == FishhookTarget.competing ? FishhookTarget.replacement : FishhookTarget.competing
            )
        }
    }

    func testOverlappingWritersKeepTheSharedPageWritable() throws {
        let section = try FishhookSection()
        let firstIndex = section.middleSlot
        let secondIndex = firstIndex + 1
        section.select(firstIndex)
        section.select(secondIndex)
        XCTAssertEqual(section.protectPage(1, protection: VM_PROT_READ), KERN_SUCCESS)
        let first = RebindingState()
        let second = RebindingState()
        let probe = ProtectionProbe(blockedSlot: vm_address_t(UInt(bitPattern: section.slots.advanced(by: firstIndex))))
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            section.rebind(first, probe: probe, at: firstIndex)
            group.leave()
        }
        let entered = probe.entered.wait(timeout: .now() + 5)
        XCTAssertEqual(entered, .success)
        if entered == .success {
            section.rebind(second, probe: probe, at: secondIndex)
            XCTAssertEqual(section.slots[secondIndex], FishhookTarget.replacement)
            XCTAssertNotEqual(section.pageProtection(1) & VM_PROT_WRITE, 0)
        }
        probe.resume.signal()
        group.wait()

        XCTAssertEqual(probe.calls, 2)
        XCTAssertEqual(first.patched, 1)
        XCTAssertEqual(second.patched, 1)
        XCTAssertEqual(first.failed, 0)
        XCTAssertEqual(second.failed, 0)
        XCTAssertEqual(section.slots[firstIndex], FishhookTarget.replacement)
        XCTAssertNotEqual(section.pageProtection(1) & VM_PROT_WRITE, 0)
    }
}

private enum FishhookTarget {
    static var original: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: 0x10000)! }
    static var replacement: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: 0x20000)! }
    static var competing: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: 0x30000)! }
}

private func protection(at location: vm_address_t) -> vm_prot_t {
    var address = location
    var size: vm_size_t = 0
    var info = vm_region_basic_info_data_64_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_region_basic_info_data_64_t>.stride / MemoryLayout<integer_t>.stride
    )
    let capacity = Int(count)
    var object: mach_port_t = 0
    let result = withUnsafeMutablePointer(to: &info) { info in
        info.withMemoryRebound(to: integer_t.self, capacity: capacity) {
            vm_region_64(mach_task_self_, &address, &size, VM_REGION_BASIC_INFO_64, $0, &count, &object)
        }
    }
    if object != 0 {
        mach_port_deallocate(mach_task_self_, object)
    }
    guard result == KERN_SUCCESS, address <= location, location - address < size else {
        return VM_PROT_NONE
    }
    return info.protection
}

// Configuration stays immutable while callbacks run; the lock protects the
// callback count and the single writer paused after gaining write access.
private final class ProtectionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var didBlock = false
    private let fails: Bool
    private let publishTarget: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    private let publication: UnsafeMutableRawPointer?
    private let blockedSlot: vm_address_t?
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    init(
        fails: Bool = false,
        publishTarget: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil,
        publication: UnsafeMutableRawPointer? = nil,
        blockedSlot: vm_address_t? = nil
    ) {
        self.fails = fails
        self.publishTarget = publishTarget
        self.publication = publication
        self.blockedSlot = blockedSlot
    }

    func protect(
        task: vm_map_t,
        address: vm_address_t,
        size: vm_size_t,
        setMaximum: boolean_t,
        protection requestedProtection: vm_prot_t
    ) -> kern_return_t {
        lock.lock()
        callCount += 1
        let shouldBlock: Bool
        if let blockedSlot, blockedSlot >= address, blockedSlot - address < size, !didBlock {
            didBlock = true
            shouldBlock = true
        } else {
            shouldBlock = false
        }
        lock.unlock()

        guard !fails else {
            return KERN_PROTECTION_FAILURE
        }
        let result = vm_protect(task, address, size, setMaximum, requestedProtection)
        guard result == KERN_SUCCESS else {
            return result
        }
        publishTarget?.pointee = publication
        if shouldBlock {
            entered.signal()
            guard resume.wait(timeout: .now() + 5) == .success else {
                return KERN_OPERATION_TIMED_OUT
            }
            // If a regression restores permissions, reject the waiting write
            // safely instead of writing through a read-only page.
            guard let blockedSlot, protection(at: blockedSlot) & VM_PROT_WRITE != 0 else {
                return KERN_PROTECTION_FAILURE
            }
        }
        return result
    }
}

private func protectFishhookSection(
    _ task: vm_map_t,
    _ address: vm_address_t,
    _ size: vm_size_t,
    _ setMaximum: boolean_t,
    _ protection: vm_prot_t,
    _ context: UnsafeMutableRawPointer?
) -> kern_return_t {
    guard let context else {
        return KERN_INVALID_ARGUMENT
    }
    return Unmanaged<ProtectionProbe>.fromOpaque(context).takeUnretainedValue().protect(
        task: task, address: address, size: size, setMaximum: setMaximum, protection: protection
    )
}

// Native atomics own these values during rebinds. Swift initializes them before
// starting workers and reads them only after all workers have finished.
private final class RebindingState: @unchecked Sendable {
    let firstTargetStorage = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
    let binding = UnsafeMutablePointer<rebinding>.allocate(capacity: 1)
    private let counters = UnsafeMutablePointer<UInt64>.allocate(capacity: 3)
    private let name = strdup("target")!

    var firstTarget: UnsafeMutableRawPointer? {
        get { firstTargetStorage.pointee }
        set { firstTargetStorage.pointee = newValue }
    }
    var patched: UInt64 { counters[0] }
    var conflicts: UInt64 { counters[1] }
    var failed: UInt64 { counters[2] }

    init() {
        firstTargetStorage.initialize(to: nil)
        counters.initialize(repeating: 0, count: 3)
        var value = rebinding()
        value.name = UnsafePointer(name)
        value.replacement = FishhookTarget.replacement
        value.first_replaced = firstTargetStorage
        value.patched_count = counters
        value.conflict_count = counters.advanced(by: 1)
        value.failed_count = counters.advanced(by: 2)
        binding.initialize(to: value)
    }

    deinit {
        firstTargetStorage.deinitialize(count: 1)
        firstTargetStorage.deallocate()
        counters.deinitialize(count: 3)
        counters.deallocate()
        binding.deinitialize(count: 1)
        binding.deallocate()
        free(name)
    }
}

// Concurrent rebinds use separate slots and read-only symbol indices. The
// allocation outlives every worker, and permission changes go through Mach.
private final class FishhookSection: @unchecked Sendable {
    let address: vm_address_t
    let size = vm_size_t(getpagesize()) * 3
    let slots: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    let slotCount: Int
    private let indices: UnsafeMutablePointer<UInt32>

    var slotsPerPage: Int { Int(size / 3) / MemoryLayout<UnsafeMutableRawPointer?>.stride }
    var middleSlot: Int { slotsPerPage + 4 }

    init() throws {
        var address: vm_address_t = 0
        let result = vm_allocate(mach_task_self_, &address, size, VM_FLAGS_ANYWHERE)
        guard result == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(result))
        }
        self.address = address
        slotCount = Int(size) / MemoryLayout<UnsafeMutableRawPointer?>.stride
        slots = UnsafeMutableRawPointer(bitPattern: address)!.bindMemory(
            to: UnsafeMutableRawPointer?.self, capacity: slotCount
        )
        slots.initialize(repeating: nil, count: slotCount)
        indices = .allocate(capacity: slotCount)
        indices.initialize(repeating: UInt32(INDIRECT_SYMBOL_LOCAL), count: slotCount)
    }

    deinit {
        indices.deinitialize(count: slotCount)
        indices.deallocate()
        vm_deallocate(mach_task_self_, address, size)
    }

    func select(_ index: Int, target: UnsafeMutableRawPointer = FishhookTarget.original) {
        indices[index] = 0
        slots[index] = target
    }

    func protectPage(_ page: Int, protection: vm_prot_t) -> kern_return_t {
        vm_protect(mach_task_self_, address + vm_address_t(page) * (size / 3), size / 3, 0, protection)
    }

    func pageProtection(_ page: Int) -> vm_prot_t {
        protection(at: address + vm_address_t(page) * (size / 3))
    }

    func rebind(_ state: RebindingState, probe: ProtectionProbe, at index: Int? = nil) {
        let offset = index ?? 0
        withExtendedLifetime((self, state, probe)) {
            dd_fishhook_rebind_section_for_testing(
                slots.advanced(by: offset),
                index == nil ? slotCount : 1,
                indices.advanced(by: offset),
                state.binding,
                protectFishhookSection,
                Unmanaged.passUnretained(probe).toOpaque()
            )
        }
    }
}

#endif
