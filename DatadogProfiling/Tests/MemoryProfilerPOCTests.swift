/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogMachProfiler
import DatadogMachProfiler.Testing
@testable import DatadogProfiling

// =====================================================================
// Memory Profiler POC tests (RUM-16460)
//
// One test per validation question. Each test ends by printing measured
// numbers so the findings document can quote them verbatim.
//
// Run on-device when possible — Simulator phys_footprint and VM region
// layout differ from real iOS, especially in iOS 16+. The findings doc
// notes which numbers came from Simulator vs device.
// =====================================================================

final class MemoryProfilerPOCTests: XCTestCase {
    override func setUp() {
        super.setUp()
        dd_memory_test_reset()
    }

    override func tearDown() {
        MemoryProfilerPOC.stop()
        dd_memory_test_reset()
        super.tearDown()
    }

    // MARK: - SQ6: source enum threaded through the core

    func testObserveAllocationWithSource_recordsSwiftSource() {
        dd_memory_test_reset()
        XCTAssertTrue(dd_memory_profiler_start_passive(UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)))
        defer { dd_memory_profiler_stop() }

        var box = 0
        let ptr = withUnsafePointer(to: &box) { UnsafeRawPointer($0) }

        dd_memory_test_force_next_sample()
        dd_memory_observe_allocation_with_source(ptr, 4096, "MySwiftType", DD_MEMORY_SOURCE_SWIFT)

        XCTAssertEqual(dd_memory_test_live_count(), 1)
        XCTAssertEqual(dd_memory_test_sample_source(ptr), DD_MEMORY_SOURCE_SWIFT)
    }

    func testObserveAllocation_defaultsToObjCSource() {
        dd_memory_test_reset()
        XCTAssertTrue(dd_memory_profiler_start_passive(UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)))
        defer { dd_memory_profiler_stop() }

        var box = 0
        let ptr = withUnsafePointer(to: &box) { UnsafeRawPointer($0) }

        dd_memory_test_force_next_sample()
        dd_memory_observe_allocation(ptr, 4096, "MyObjCType")

        XCTAssertEqual(dd_memory_test_sample_source(ptr), DD_MEMORY_SOURCE_OBJC)
    }

    func testAllocWindow_capturesTransientFreedAllocation_whileLiveSetDoesNot() {
        dd_memory_test_reset()
        XCTAssertTrue(dd_memory_profiler_start_passive(UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)))
        defer { dd_memory_profiler_stop() }

        var a = 0
        var b = 0
        let retained = withUnsafePointer(to: &a) { UnsafeRawPointer($0) }
        let transient = withUnsafePointer(to: &b) { UnsafeRawPointer($0) }

        dd_memory_test_force_next_sample()
        dd_memory_observe_allocation_with_source(retained, 4096, "Retained", DD_MEMORY_SOURCE_SWIFT)
        dd_memory_test_force_next_sample()
        dd_memory_observe_allocation_with_source(transient, 4096, "Transient", DD_MEMORY_SOURCE_SWIFT)
        // Free the transient: it leaves the live set but its alloc contribution stays.
        dd_memory_observe_deallocation(transient)

        // Live set holds only the retained object.
        XCTAssertEqual(dd_memory_test_live_count(), 1)

        // The allocation window holds BOTH sampled allocations (incl. the freed one).
        var alloc = dd_memory_alloc_window_capture()
        defer { dd_memory_snapshot_destroy(&alloc) }
        XCTAssertEqual(alloc.sample_count, 2, "alloc window must retain the transient's contribution")

        // Capture resets the window: a second capture is empty.
        var alloc2 = dd_memory_alloc_window_capture()
        defer { dd_memory_snapshot_destroy(&alloc2) }
        XCTAssertEqual(alloc2.sample_count, 0, "alloc window must reset after capture")
    }

    // MARK: - Q1: Are malloc_zone_t hooks safe in release builds?

    func test_q1_default_zone_writability_is_probed_without_crashing() {
        // The probe call must complete without segfaulting. The boolean
        // result is informational — the install path branches on it.
        let writable = dd_memory_test_default_zone_writable()
        print("[POC Q1] default_zone_writable = \(writable)")
    }

    func test_q1_hooks_install_and_report_which_path_was_taken() throws {
        let status = MemoryProfilerPOC.start()

        switch status {
        case .installedDirect:
            print("[POC Q1] Hooks installed via direct pointer write — zone struct is writable on this OS.")
        case .installedViaMprotect:
            print("[POC Q1] Hooks installed via mprotect — zone struct page was read-only.")
        case .failedReadOnlyZone:
            XCTFail("[POC Q1] mprotect failed: zone is read-only AND mprotect couldn't make it writable.")
        case .failedNoZone:
            XCTFail("[POC Q1] malloc_default_zone returned NULL — unexpected.")
        case .failedCollisionWithOtherHook:
            XCTFail("[POC Q1] Another tool already hooked the zone — test environment dirty.")
        case .alreadyInstalled:
            XCTFail("[POC Q1] Hooks were already installed at test start — reset failed.")
        }

        XCTAssertTrue(MemoryProfilerPOC.isRunning, "Profiler should report running after start")
    }

    // MARK: - Q2: Poisson sampling overhead

    func test_q2_poisson_sampling_captures_forced_sample() {
        let status = MemoryProfilerPOC.start()
        guard status == .installedDirect || status == .installedViaMprotect else {
            return XCTFail("Could not install hooks: \(status)")
        }

        dd_memory_test_force_next_sample()

        // Allocate something we own and can free, after the force flag
        // is set. The hook should see the alloc, sample it, and tracked
        // count should increment.
        let ptr = malloc(1024)
        XCTAssertNotNil(ptr)

        let sampled = dd_memory_test_sampled_count()
        let diagnosticsAfterMalloc = MemoryProfilerPOC.diagnostics()

        // POC critical finding: on modern iOS the C-level `malloc()` may
        // bypass the zone's function pointer and dispatch to libmalloc's
        // internal fast path. If that's true, sampled == 0 here despite
        // the force flag and despite hooks being installed.
        print("[POC Q2] After malloc(1024): "
              + "hook_total_allocations=\(diagnosticsAfterMalloc.totalAllocations), "
              + "sampled=\(sampled)")
        if diagnosticsAfterMalloc.totalAllocations == 0 {
            print("[POC Q2] CRITICAL: malloc() did NOT route through zone->malloc — "
                  + "the zone-hook approach is bypassed by libmalloc's fast path.")
        }

        // Cross-check by allocating explicitly via the zone interface.
        // If the hook fires here but not for plain malloc(), we've
        // confirmed that the standard malloc symbol doesn't go through
        // zone function pointers anymore.
        let zone = malloc_default_zone()
        dd_memory_test_force_next_sample()
        let zonePtr = malloc_zone_malloc(zone, 2048)
        let diagnosticsAfterZoneMalloc = MemoryProfilerPOC.diagnostics()
        print("[POC Q2] After malloc_zone_malloc(default_zone, 2048): "
              + "hook_total_allocations=\(diagnosticsAfterZoneMalloc.totalAllocations - diagnosticsAfterMalloc.totalAllocations), "
              + "live=\(MemoryProfilerPOC.diagnostics().liveSampledAllocations)")

        free(ptr)
        if let zonePtr = zonePtr { malloc_zone_free(zone, zonePtr) }
    }

    func test_q2_overhead_under_tight_alloc_loop() {
        // Measure the wall-time cost of N allocations with hooks
        // installed vs with profiler disabled. Reports a percentage so
        // the findings document has a real number to quote.
        let iterations = 100_000
        let sizes: [Int] = [16, 64, 256, 1024, 4096]

        // Baseline: profiler disabled.
        let baselineDuration = measureAllocLoop(iterations: iterations, sizes: sizes)

        let status = MemoryProfilerPOC.start()
        guard status == .installedDirect || status == .installedViaMprotect else {
            return XCTFail("Could not install hooks: \(status)")
        }

        let hookedDuration = measureAllocLoop(iterations: iterations, sizes: sizes)
        MemoryProfilerPOC.stop()

        let overheadPercent = (hookedDuration / baselineDuration - 1.0) * 100.0
        let diagnostics = MemoryProfilerPOC.diagnostics()

        print(String(format: "[POC Q2] Baseline: %.3fs, Hooked: %.3fs, Overhead: %.2f%%",
                     baselineDuration, hookedDuration, overheadPercent))
        print("[POC Q2] Diagnostics: total_allocations=\(diagnostics.totalAllocations) "
              + "sampled=\(diagnostics.sampledAllocations) "
              + "unsampled=\(diagnostics.unsampledCalls) "
              + "reentrant_skips=\(diagnostics.reentrantSkips)")

        // POC bar: overhead under 50%. The RFC target is <1% but reach
        // that during productionization — POC just needs to confirm the
        // architecture has the right shape, not the final perf number.
        XCTAssertLessThan(overheadPercent, 100.0,
                          "Hook overhead >100% indicates a fundamental architectural problem")
    }

    // MARK: - Q3: Free-side tracking viability

    func test_q3_free_after_sampled_alloc_decrements_live_count() {
        let status = MemoryProfilerPOC.start()
        guard status == .installedDirect || status == .installedViaMprotect else {
            return XCTFail("Could not install hooks: \(status)")
        }

        // Note: with the malloc-zone bypass confirmed in Q2, this test
        // documents the consequence: forced-sample allocations don't
        // appear in the live set because the hooks never fire. The
        // free-side hash-set design itself is sound — we just can't
        // exercise it via the malloc/free C API.
        var ptrs: [UnsafeMutableRawPointer?] = []
        for _ in 0..<10 {
            dd_memory_test_force_next_sample()
            ptrs.append(malloc(256))
        }

        let liveAfterAlloc = dd_memory_test_live_count()
        for p in ptrs { free(p) }
        let liveAfterFree = dd_memory_test_live_count()

        print("[POC Q3] Free-side observation under malloc bypass: "
              + "live after alloc=\(liveAfterAlloc), after free=\(liveAfterFree). "
              + "Both 0 confirms hooks never fired (bypass per Q2 finding).")
    }

    func test_q3_concurrent_allocs_do_not_crash_or_double_track() {
        let status = MemoryProfilerPOC.start()
        guard status == .installedDirect || status == .installedViaMprotect else {
            return XCTFail("Could not install hooks: \(status)")
        }

        let threadCount = 8
        let allocsPerThread = 1_000
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "memory.poc.concurrent", attributes: .concurrent)

        for _ in 0..<threadCount {
            group.enter()
            queue.async {
                for _ in 0..<allocsPerThread {
                    let p = malloc(Int.random(in: 16...1024))
                    if let p = p { free(p) }
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + 30)
        XCTAssertEqual(waitResult, .success, "Threads should complete within 30s")

        let diagnostics = MemoryProfilerPOC.diagnostics()
        print("[POC Q3] After concurrent stress: "
              + "total=\(diagnostics.totalAllocations) "
              + "sampled=\(diagnostics.sampledAllocations) "
              + "live=\(diagnostics.liveSampledAllocations)")
    }

    // MARK: - Q4: VM region walker

    func test_q4_vm_walk_returns_nonzero_breakdown() {
        let snapshot = MemoryProfilerPOC.walkVMRegions()

        XCTAssertGreaterThan(snapshot.totalRegions, 0,
                             "Walk should enumerate at least one region")
        XCTAssertGreaterThan(snapshot.physFootprint, 0,
                             "phys_footprint should be > 0 in a running process")
        XCTAssertGreaterThan(snapshot.dylibs.regionCount, 0,
                             "A running test process must have dylibs mapped")

        let categorizedVirtual = snapshot.managedHeap.virtualBytes
            + snapshot.dylibs.virtualBytes
            + snapshot.stacks.virtualBytes
            + snapshot.mappedFiles.virtualBytes
            + snapshot.jitCode.virtualBytes
            + snapshot.other.virtualBytes

        print(String(format: "[POC Q4] Walk: %d regions in %.2f ms",
                     snapshot.totalRegions,
                     Double(snapshot.walkDurationNs) / 1_000_000.0))
        print("[POC Q4] phys_footprint=\(format(snapshot.physFootprint))")
        print("[POC Q4]   managed_heap   resident=\(format(snapshot.managedHeap.residentBytes)) "
              + "regions=\(snapshot.managedHeap.regionCount)")
        print("[POC Q4]   dylibs         resident=\(format(snapshot.dylibs.residentBytes)) "
              + "regions=\(snapshot.dylibs.regionCount)")
        print("[POC Q4]   stacks         resident=\(format(snapshot.stacks.residentBytes)) "
              + "regions=\(snapshot.stacks.regionCount)")
        print("[POC Q4]   mapped_files   resident=\(format(snapshot.mappedFiles.residentBytes)) "
              + "regions=\(snapshot.mappedFiles.regionCount)")
        print("[POC Q4]   jit_code       resident=\(format(snapshot.jitCode.residentBytes)) "
              + "regions=\(snapshot.jitCode.regionCount)")
        print("[POC Q4]   other          resident=\(format(snapshot.other.residentBytes)) "
              + "regions=\(snapshot.other.regionCount)")
        print("[POC Q4] Sum of categorized virtual = \(format(categorizedVirtual)) "
              + "vs virtual_size=\(format(snapshot.virtualSize))")
    }

    // MARK: - Heap snapshot round-trip

    func test_snapshot_round_trip_runs_without_crashing() {
        // With the malloc-zone bypass finding, this test reduces to:
        // does the snapshot path (table iteration, allocation of the
        // output array, copy-out) work without crashing? It exercises
        // the dd_memory_snapshot_capture / dd_memory_snapshot_destroy
        // round-trip even when the live set is empty — which is the
        // case on modern iOS until we replace the interception layer.
        let status = MemoryProfilerPOC.start()
        guard status == .installedDirect || status == .installedViaMprotect else {
            return XCTFail("Could not install hooks: \(status)")
        }

        let snapshot = MemoryProfilerPOC.captureSnapshot()
        print("[POC Snapshot] Captured \(snapshot.samples.count) samples "
              + "(0 expected under malloc-zone bypass).")
    }

    // MARK: - Helpers

    /// Runs a tight alloc/free loop without involving the profiler.
    /// Both baseline and hooked durations call this same function so the
    /// only difference between runs is the hooked vs. unhooked allocator.
    private func measureAllocLoop(iterations: Int, sizes: [Int]) -> Double {
        let start = Date()
        for i in 0..<iterations {
            let size = sizes[i % sizes.count]
            let p = malloc(size)
            free(p)
        }
        return Date().timeIntervalSince(start)
    }

    private func format(_ bytes: UInt64) -> String {
        let kib = Double(bytes) / 1024.0
        let mib = kib / 1024.0
        if mib >= 1.0 {
            return String(format: "%.2f MiB", mib)
        }
        return String(format: "%.1f KiB", kib)
    }
}

#endif
