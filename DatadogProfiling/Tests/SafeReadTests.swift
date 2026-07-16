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

// These tests exercise the safe-read path used by the Mach sampling profiler.
// Because vm_read_overwrite never raises EXC_BAD_ACCESS, the debugger does not
// need to be detached - no signal or Mach exception is generated for unmapped reads.
final class SafeReadTests: XCTestCase {
    // MARK: - Basic correctness

    func testReadStackRegionWithValidAddress() {
        // Given: a known value on the current stack
        var sentinel: UInt64 = 0x1122334455667788
        var buf = [UInt8](repeating: 0, count: 128)

        // When: reading the stack region starting at the sentinel's address
        let bytesRead = withUnsafeMutablePointer(to: &sentinel) { spPtr in
            buf.withUnsafeMutableBytes { bufPtr in
                read_stack_region_for_testing(spPtr, bufPtr.baseAddress!, 128)
            }
        }

        // Then: at least 8 bytes are returned and the sentinel is at offset 0
        XCTAssertGreaterThanOrEqual(bytesRead, MemoryLayout<UInt64>.size)
        let readBack = buf.withUnsafeBytes { $0.load(as: UInt64.self) }
        XCTAssertEqual(readBack, 0x1122334455667788)
    }

    func testReadStackRegionWithUnmappedAddress() {
        // Given: an address that is not mapped in this process
        let unmapped = UnsafeMutableRawPointer(bitPattern: 0xDEADBEEF)!
        var buf = [UInt8](repeating: 0xFF, count: 128)

        // When
        let bytesRead = buf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(unmapped, bufPtr.baseAddress!, 128)
        }

        // Then: vm_read_overwrite returns an error - no signal, no crash, 0 bytes
        XCTAssertEqual(bytesRead, 0)
    }

    func testReadStackRegionWithNullAddress() {
        // Given
        var buf = [UInt8](repeating: 0, count: 16)

        // When
        let bytesRead = buf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(nil, bufPtr.baseAddress!, 128)
        }

        // Then
        XCTAssertEqual(bytesRead, 0)
    }

    func testReadAcrossPartialUnmapReturnsReadablePrefix() {
        // Given: three contiguous pages with the middle page deallocated.
        // The fast full-region vm_read_overwrite fails, then the fallback reads
        // the contiguous mapped prefix page-by-page.
        let pageSize = vm_size_t(getpagesize())
        let totalSize = pageSize * 3

        var addr: vm_address_t = 0
        let allocResult = vm_allocate(mach_task_self_, &addr, totalSize, VM_FLAGS_ANYWHERE)
        XCTAssertEqual(allocResult, KERN_SUCCESS, "vm_allocate failed")

        // Fault the first page in so we know it is mapped and readable.
        UnsafeMutableRawPointer(bitPattern: UInt(addr))!
            .storeBytes(of: UInt64(0xAABBCCDD), as: UInt64.self)

        // Punch a hole: deallocate the middle page only.
        let middleAddr = addr + vm_address_t(pageSize)
        let deallocMiddle = vm_deallocate(mach_task_self_, middleAddr, pageSize)
        XCTAssertEqual(deallocMiddle, KERN_SUCCESS, "vm_deallocate(middle) failed")

        defer {
            // Cleanup remaining pages.
            vm_deallocate(mach_task_self_, addr, pageSize)
            vm_deallocate(mach_task_self_, addr + 2 * vm_address_t(pageSize), pageSize)
        }

        var buf = [UInt8](repeating: 0, count: Int(totalSize))
        let startPtr = UnsafeMutableRawPointer(bitPattern: UInt(addr))!

        // When: reading across the unmapped hole.
        let bytesAcross = buf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(startPtr, bufPtr.baseAddress!, Int(totalSize))
        }

        // Then: the readable prefix is preserved instead of losing the sample.
        XCTAssertEqual(bytesAcross, Int(pageSize), "Fallback should keep the first readable page")
        let readBack = buf.withUnsafeBytes { $0.load(as: UInt64.self) }
        XCTAssertEqual(readBack, 0xAABBCCDD)

        // And: reading only within the first mapped page still succeeds.
        let bytesFirst = buf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(startPtr, bufPtr.baseAddress!, Int(pageSize))
        }
        XCTAssertEqual(bytesFirst, Int(pageSize), "Reading entirely within a mapped page must succeed")
    }

    func testReadAcrossPartialUnmapFromUnalignedAddressReturnsReadablePrefix() {
        // Given: a read starting near the end of a mapped page and crossing into
        // an unmapped page. This exercises the fallback chunk sizing for SP
        // values that are not page-aligned.
        let pageSize = vm_size_t(getpagesize())
        let readablePrefixSize = 32
        let totalSize = pageSize * 2

        var addr: vm_address_t = 0
        let allocResult = vm_allocate(mach_task_self_, &addr, totalSize, VM_FLAGS_ANYWHERE)
        XCTAssertEqual(allocResult, KERN_SUCCESS, "vm_allocate failed")

        let secondPageAddr = addr + vm_address_t(pageSize)
        let deallocSecond = vm_deallocate(mach_task_self_, secondPageAddr, pageSize)
        XCTAssertEqual(deallocSecond, KERN_SUCCESS, "vm_deallocate(second) failed")

        defer {
            vm_deallocate(mach_task_self_, addr, pageSize)
        }

        let startAddress = addr + vm_address_t(Int(pageSize) - readablePrefixSize)
        let startPtr = UnsafeMutableRawPointer(bitPattern: UInt(startAddress))!
        memset(startPtr, 0xAB, readablePrefixSize)

        var buf = [UInt8](repeating: 0, count: readablePrefixSize * 2)
        let requestedSize = buf.count

        // When
        let bytesRead = buf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(startPtr, bufPtr.baseAddress!, requestedSize)
        }

        // Then
        XCTAssertEqual(bytesRead, readablePrefixSize)
        XCTAssertEqual(Array(buf.prefix(readablePrefixSize)), Array(repeating: 0xAB, count: readablePrefixSize))
    }

    // MARK: - Recovery and reuse

    func testRecoveryAfterInvalidRead() {
        // Given: an invalid address followed by a valid one
        var sentinel: UInt64 = 42
        var buf = [UInt8](repeating: 0, count: 128)
        let unmapped = UnsafeMutableRawPointer(bitPattern: 0xDEADBEEF)!

        // When: first read fails
        let failedBytes = buf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(unmapped, bufPtr.baseAddress!, 128)
        }
        XCTAssertEqual(failedBytes, 0, "Read from unmapped address should return 0 bytes")

        // When: subsequent read from a valid address succeeds
        let successBytes = withUnsafeMutablePointer(to: &sentinel) { spPtr in
            buf.withUnsafeMutableBytes { bufPtr in
                read_stack_region_for_testing(spPtr, bufPtr.baseAddress!, 128)
            }
        }
        XCTAssertGreaterThanOrEqual(successBytes, MemoryLayout<UInt64>.size)
        let readBack = buf.withUnsafeBytes { $0.load(as: UInt64.self) }
        XCTAssertEqual(readBack, 42)
    }

    // MARK: - Concurrency

    func testConcurrentReadsDoNotCrash() {
        // Given: many threads simultaneously reading valid and invalid addresses
        let iterations = 500
        let expectation = self.expectation(description: "Concurrent stack region reads")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            var buf = [UInt8](repeating: 0, count: 128)

            if index.isMultiple(of: 2) {
                // Valid: read from a live stack variable
                var value = UInt64(index)
                let bytes = withUnsafeMutablePointer(to: &value) { spPtr in
                    buf.withUnsafeMutableBytes { bufPtr in
                        read_stack_region_for_testing(spPtr, bufPtr.baseAddress!, 128)
                    }
                }
                XCTAssertGreaterThan(bytes, 0, "Valid read on iteration \(index) should return > 0 bytes")
            } else {
                // Invalid: unmapped address - must return 0, must not crash
                let unmapped = UnsafeMutableRawPointer(bitPattern: 0xDEADBEEF)!
                let bytes = buf.withUnsafeMutableBytes { bufPtr in
                    read_stack_region_for_testing(unmapped, bufPtr.baseAddress!, 128)
                }
                XCTAssertEqual(bytes, 0, "Invalid read on iteration \(index) should return 0 bytes")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Walk termination on garbage frame pointers

    func testWalkTerminatesOnGarbageFramePointer() {
        let maxDepth: UInt32 = 10
        let stackBase: UInt = 0x1_0000_0000
        let bufSize = 256
        let validPC = UnsafeMutableRawPointer(bitPattern: 0x40_0000)!

        let subcases: [(name: String, fp: UnsafeMutableRawPointer)] = [
            ("unaligned FP", UnsafeMutableRawPointer(bitPattern: stackBase + 0x11)!),
            ("FP below stack_base", UnsafeMutableRawPointer(bitPattern: stackBase - 0x100)!),
            ("FP below MIN_USERSPACE_ADDR", UnsafeMutableRawPointer(bitPattern: 0x8)!),
            ("FP above MAX_USERSPACE_ADDR", UnsafeMutableRawPointer(bitPattern: 0x8000_0000_0000)!),
            ("FP beyond bytes_read", UnsafeMutableRawPointer(bitPattern: stackBase + UInt(bufSize) + 0x100)!)
        ]

        for subcase in subcases {
            let count = runWalk(
                initialFP: subcase.fp,
                initialPC: validPC,
                stackBase: stackBase,
                bufSize: bufSize,
                maxDepth: maxDepth
            )
            let message = "\(subcase.name): walk should record only the initial PC and stop"
            XCTAssertEqual(count, 1, message)
        }
    }

    func testWalkStopsAtInvalidSavedPC() {
        let maxDepth: UInt32 = 10
        let stackBase: UInt = 0x1_0000_0000
        let bufSize = 256
        let validPC1 = UnsafeMutableRawPointer(bitPattern: 0x40_0000)!
        let validPC2 = UnsafeMutableRawPointer(bitPattern: 0x50_0000)!
        let initialFP = UnsafeMutableRawPointer(bitPattern: stackBase + 0x40)!

        let count = runWalk(
            initialFP: initialFP,
            initialPC: validPC1,
            stackBase: stackBase,
            bufSize: bufSize,
            maxDepth: maxDepth
        ) { ptr in
            // Frame at offset 0x40: saved_fp = stackBase + 0x80 (valid), saved_pc = validPC2 (valid)
            let frame1 = ptr.advanced(by: 0x40).assumingMemoryBound(to: UInt.self)
            frame1[0] = stackBase + 0x80
            frame1[1] = UInt(bitPattern: validPC2)

            // Frame at offset 0x80: saved_fp = valid, saved_pc = 0 (invalid)
            let frame2 = ptr.advanced(by: 0x80).assumingMemoryBound(to: UInt.self)
            frame2[0] = stackBase + 0xC0
            frame2[1] = 0
        }

        let message = "Walk should record validPC1 + validPC2 then stop when the next saved PC is invalid"
        XCTAssertEqual(count, 2, message)
    }

    func testWalkUsesSafeReadFallbackWhenValidFramePointerIsOutsideSnapshot() {
        let maxDepth: UInt32 = 4
        let pageSize = vm_size_t(getpagesize())
        let totalSize = pageSize * 2

        var addr: vm_address_t = 0
        let allocResult = vm_allocate(mach_task_self_, &addr, totalSize, VM_FLAGS_ANYWHERE)
        guard allocResult == KERN_SUCCESS else {
            XCTFail("vm_allocate failed")
            return
        }
        defer { vm_deallocate(mach_task_self_, addr, totalSize) }

        let stackBase = UInt(addr)
        let firstFrameAddress = stackBase + UInt(pageSize) + 0x40
        let secondFrameAddress = firstFrameAddress + 0x40
        let validPC1 = UnsafeMutableRawPointer(bitPattern: 0x40_0000)!
        let validPC2 = UnsafeMutableRawPointer(bitPattern: 0x50_0000)!

        let firstFrame = UnsafeMutableRawPointer(bitPattern: firstFrameAddress)!.assumingMemoryBound(to: UInt.self)
        firstFrame[0] = secondFrameAddress
        firstFrame[1] = UInt(bitPattern: validPC2)

        let secondFrame = UnsafeMutableRawPointer(bitPattern: secondFrameAddress)!.assumingMemoryBound(to: UInt.self)
        secondFrame[0] = secondFrameAddress + 0x40
        secondFrame[1] = 0

        let count = runWalk(
            initialFP: UnsafeMutableRawPointer(bitPattern: firstFrameAddress)!,
            initialPC: validPC1,
            stackBase: stackBase,
            bufSize: 128,
            maxDepth: maxDepth,
            useSafeReadFallback: true
        )

        XCTAssertEqual(count, 2, "Safe-read fallback should follow valid frame pointers outside the initial snapshot")
    }

    func testWalkTerminatesOnFramePointerCycle() {
        // A self-referential frame: the saved FP at offset 0x40 points back to
        // offset 0x40, with a valid saved PC so the walk doesn't bail on the PC
        // guard. The loop must still terminate at max_depth.
        let maxDepth: UInt32 = 16
        let stackBase: UInt = 0x1_0000_0000
        let bufSize = 256
        let validPC = UnsafeMutableRawPointer(bitPattern: 0x40_0000)!
        let cycleOffset: UInt = 0x40
        let cycleFP = UnsafeMutableRawPointer(bitPattern: stackBase + cycleOffset)!

        let count = runWalk(
            initialFP: cycleFP,
            initialPC: validPC,
            stackBase: stackBase,
            bufSize: bufSize,
            maxDepth: maxDepth
        ) { ptr in
            let words = ptr.advanced(by: Int(cycleOffset)).assumingMemoryBound(to: UInt.self)
            words[0] = stackBase + cycleOffset
            words[1] = UInt(bitPattern: validPC)
        }

        XCTAssertEqual(count, maxDepth, "FP cycle should iterate until max_depth and stop")
    }

    // MARK: - Mach exception handler is not triggered

    #if !os(tvOS)
    // thread_get_exception_ports / thread_set_exception_ports / mach_msg are not
    // available on tvOS, so this regression test is iOS-only.
    func testMachExceptionHandlerNotTriggeredByUnmappedRead() {
        // Pins the Crashlytics fix: vm_read_overwrite must not raise EXC_BAD_ACCESS,
        // otherwise a Mach exception handler installed on the current thread would
        // receive a message before the kernel converts to SIGBUS/SIGSEGV.

        var exceptionPort: mach_port_t = 0
        var kr = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &exceptionPort)
        XCTAssertEqual(kr, KERN_SUCCESS, "mach_port_allocate failed")
        defer {
            // Release the send right we inserted (below), then the receive right
            // we allocated above. mach_port_destroy is deprecated since macOS 12.
            mach_port_deallocate(mach_task_self_, exceptionPort)
            mach_port_mod_refs(mach_task_self_, exceptionPort, MACH_PORT_RIGHT_RECEIVE, -1)
        }

        kr = mach_port_insert_right(
            mach_task_self_,
            exceptionPort,
            exceptionPort,
            mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND)
        )
        XCTAssertEqual(kr, KERN_SUCCESS, "mach_port_insert_right failed")

        let currentThread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, currentThread) }

        let mask = exception_mask_t(1 << EXC_BAD_ACCESS) | exception_mask_t(1 << EXC_BAD_INSTRUCTION)

        var savedMasks = [exception_mask_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var savedPorts = [mach_port_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var savedBehavior = [exception_behavior_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var savedFlavor = [thread_state_flavor_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var savedCount = mach_msg_type_number_t(EXC_TYPES_COUNT)

        kr = thread_get_exception_ports(
            currentThread,
            mask,
            &savedMasks,
            &savedCount,
            &savedPorts,
            &savedBehavior,
            &savedFlavor
        )
        XCTAssertEqual(kr, KERN_SUCCESS, "thread_get_exception_ports failed")

        kr = thread_set_exception_ports(
            currentThread,
            mask,
            exceptionPort,
            exception_behavior_t(EXCEPTION_DEFAULT),
            THREAD_STATE_NONE
        )
        XCTAssertEqual(kr, KERN_SUCCESS, "thread_set_exception_ports failed")
        defer {
            for index in 0..<Int(savedCount) {
                thread_set_exception_ports(
                    currentThread,
                    savedMasks[index],
                    savedPorts[index],
                    savedBehavior[index],
                    savedFlavor[index]
                )
            }
        }

        // Listener thread waits up to 500ms for an exception message.
        // Timeout = no exception was raised; receive = safe-read regressed.
        let listenerDone = DispatchSemaphore(value: 0)
        let receivedLock = NSLock()
        var didReceiveMessage = false

        DispatchQueue.global().async {
            let bufferSize: mach_msg_size_t = 1_024
            var buffer = [UInt8](repeating: 0, count: Int(bufferSize))
            let result = buffer.withUnsafeMutableBytes { ptr -> mach_msg_return_t in
                let header = ptr.baseAddress!.assumingMemoryBound(to: mach_msg_header_t.self)
                return mach_msg(
                    header,
                    MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                    0,
                    bufferSize,
                    exceptionPort,
                    500,
                    0
                )
            }
            receivedLock.lock()
            didReceiveMessage = (result == MACH_MSG_SUCCESS)
            receivedLock.unlock()
            listenerDone.signal()
        }

        // Trigger an unmapped read. vm_read_overwrite must return 0 without
        // raising anything that reaches the exception port.
        var readBuf = [UInt8](repeating: 0, count: 128)
        let unmapped = UnsafeMutableRawPointer(bitPattern: 0xDEAD_BEEF)!
        let bytesRead = readBuf.withUnsafeMutableBytes { bufPtr in
            read_stack_region_for_testing(unmapped, bufPtr.baseAddress!, 128)
        }
        XCTAssertEqual(bytesRead, 0, "Unmapped vm_read_overwrite must return 0")

        let waitResult = listenerDone.wait(timeout: .now() + 1.5)
        XCTAssertEqual(waitResult, .success, "Listener should complete (timed out, as expected)")

        receivedLock.lock()
        let gotMessage = didReceiveMessage
        receivedLock.unlock()

        let regressionMessage = "Mach exception handler must NOT receive a message - this is the Crashlytics fix"
        XCTAssertFalse(gotMessage, regressionMessage)
    }
    #endif // !os(tvOS)

    // MARK: - End-to-end: frame capture via the full profiler

    func testProfilerCapturesFramesFromSuspendedThread() {
            // This exercises the complete path: thread_get_frame_pointers -> read_stack_region
            // -> memcpy frame walk, all without raising any memory fault.
        let mockThread = MockThread {
            XCTAssertEqual(dd_profiler_start(), 1)

            // Provide a non-trivial call stack so the profiler has frames to walk.
            recursiveWork(depth: 10) {
                Thread.sleep(forTimeInterval: 0.05)
            }

            dd_profiler_stop()

            let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
            XCTAssertGreaterThan(sampleCount, 0, "Profiler should capture stack frames via batch read")

            dd_profiler_destroy()
        }

        mockThread.start()
        XCTAssertTrue(mockThread.waitForWorkCompletion(timeout: 5.0))
        mockThread.cancel()
    }
}

// MARK: - Helpers

private func recursiveWork(depth: Int, work: @escaping () -> Void) {
    guard depth > 0 else {
        work()
        return
    }
    recursiveWork(depth: depth - 1, work: work)
}

/// Drives the frame walker against a synthetic stack buffer. The caller can populate
/// the buffer via the `populate` closure before the walk runs.
///
/// Returns the resulting `frame_count` so callers can assert how many frames the
/// walk recorded before terminating on a guard.
private func runWalk(
    initialFP: UnsafeMutableRawPointer,
    initialPC: UnsafeMutableRawPointer,
    stackBase: UInt,
    bufSize: Int,
    maxDepth: UInt32,
    useSafeReadFallback: Bool = false,
    populate: (UnsafeMutableRawPointer) -> Void = { _ in }
) -> UInt32 {
    var buf = [UInt8](repeating: 0, count: bufSize)
    var frames = [stack_frame_t](repeating: stack_frame_t(), count: Int(maxDepth))
    var trace = stack_trace_t()

    return frames.withUnsafeMutableBufferPointer { framesPtr in
        trace.frames = framesPtr.baseAddress
        return buf.withUnsafeMutableBytes { bufPtr in
            populate(bufPtr.baseAddress!)
            if useSafeReadFallback {
                walk_frames_with_safe_read_fallback_for_testing(
                    &trace,
                    initialFP,
                    initialPC,
                    stackBase,
                    bufPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    bufSize,
                    maxDepth
                )
            } else {
                walk_frames_in_buffer(
                    &trace,
                    initialFP,
                    initialPC,
                    stackBase,
                    bufPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    bufSize,
                    maxDepth
                )
            }
            return trace.frame_count
        }
    }
}
#endif // !os(watchOS)
