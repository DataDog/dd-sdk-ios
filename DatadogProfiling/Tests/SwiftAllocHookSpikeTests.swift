/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogMachProfiler
import DatadogMachProfiler.Testing

// =====================================================================
// swift_allocObject interception spike — Tests (SQ1..SQ3)
//
// Validates that pure-Swift class allocations (which bypass the
// +allocWithZone: swizzle) can be intercepted via symbol rebinding of
// swift_allocObject / swift_deallocClassInstance, and that we can
// recover the type name and instance size.
//
// Each test prints measured numbers so the findings can quote them.
// The hook is process-wide and installed once (never-restore), so
// invocation counts include all pure-Swift class allocations while
// enabled; tests therefore assert deltas/dominant signals, not exact
// equality.
// =====================================================================

// MARK: - Fixtures

/// Pure Swift class — allocated by swift_allocObject, NOT +allocWithZone:.
private final class PureSwiftSpikeFixture {
    var a: Int = 0
    var b: Int = 0
}

/// A second pure-Swift class used for the name/size capture case.
private final class NamedPureSwiftFixture {
    var payload: Double = 0
}

/// Swift subclass of NSObject — takes the Obj-C allocation path, so it must
/// NOT be observed by the swift_allocObject hook (proves the disjoint paths).
private class NSObjectSpikeFixture: NSObject {
    var y: Int = 0
}

/// Pure-Swift class used for the free-side live-set lifecycle (SQ4).
private final class SQ4Fixture {
    var a: Int = 0
}

/// Pure-Swift class used for the concurrency storm (SQ5).
private final class SQ5Fixture {
    var x: Int = 0
}

final class SwiftAllocHookSpikeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = dd_swift_alloc_hook_start(UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES))
        dd_swift_alloc_test_reset()
    }

    override func tearDown() {
        dd_swift_alloc_hook_stop()
        dd_swift_alloc_test_reset()
        super.tearDown()
    }

    // MARK: - SQ6: pure-Swift allocs land in the shared live-set with SWIFT source

    func test_sq6_swift_alloc_records_into_shared_table_with_source() {
        dd_memory_test_reset()
        dd_swift_alloc_test_reset()
        // Shared sampler comes up via the hook's own start().
        XCTAssertNotEqual(dd_swift_alloc_hook_start(UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)),
                          DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL)
        defer { dd_swift_alloc_hook_stop(); dd_memory_profiler_stop() }

        XCTAssertTrue(dd_memory_profiler_is_running(), "hook start must bring up the passive sampler")

        dd_memory_test_force_next_sample()
        let live0 = dd_memory_test_live_count()
        let obj = NamedPureSwiftFixture()
        withExtendedLifetime(obj) {
            XCTAssertEqual(dd_memory_test_live_count(), live0 + 1,
                           "sampled Swift alloc must enter the shared live-set")
        }
    }

    // MARK: - SQ1: does the rebinding install and bind both symbols?

    func test_sq1_rebinding_installs_and_binds_symbols() {
        let status = dd_swift_alloc_hook_start(UInt64(DD_MEMORY_POISSON_DEFAULT_RATE_BYTES)) // already installed by setUp
        XCTAssertTrue(
            status == DD_SWIFT_ALLOC_HOOK_OK || status == DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED,
            "start must succeed; got \(status)"
        )
        let diag = dd_swift_alloc_hook_diagnostics()
        print("[Swift SQ1] alloc_bound=\(diag.alloc_bound) dealloc_bound=\(diag.dealloc_bound)")
        XCTAssertTrue(diag.alloc_bound, "swift_allocObject slot must be rebound")
        XCTAssertTrue(diag.dealloc_bound, "swift_deallocClassInstance slot must be rebound")
    }

    // MARK: - SQ2: fires for a pure-Swift class, not for an NSObject subclass

    func test_sq2_fires_for_pure_swift_not_nsobject() {
        let n = 5_000
        var sink = 0

        let pureBefore = dd_swift_alloc_hook_diagnostics().alloc_invocations
        for _ in 0..<n {
            let o = PureSwiftSpikeFixture()
            o.a = 1
            sink &+= o.a
        }
        let pureDelta = dd_swift_alloc_hook_diagnostics().alloc_invocations - pureBefore

        let nsBefore = dd_swift_alloc_hook_diagnostics().alloc_invocations
        for _ in 0..<n {
            let o = NSObjectSpikeFixture()
            o.y = 1
            sink &+= o.y
        }
        let nsDelta = dd_swift_alloc_hook_diagnostics().alloc_invocations - nsBefore
        _ = sink

        print("[Swift SQ2] pure-Swift delta=\(pureDelta) (expect >= \(n)), " +
              "NSObject-subclass delta=\(nsDelta) (expect ~0)")
        XCTAssertGreaterThanOrEqual(
            pureDelta, UInt64(n),
            "pure-Swift class allocations must be observed via swift_allocObject"
        )
        XCTAssertLessThan(
            nsDelta, UInt64(n) / 10,
            "NSObject-subclass allocations must NOT go through swift_allocObject"
        )
    }

    // MARK: - SQ3: recover the type name and instance size

    func test_sq3_recovers_type_name_and_size() {
        dd_swift_alloc_test_reset()
        dd_swift_alloc_test_arm_capture()
        let obj = NamedPureSwiftFixture()
        obj.payload = 1 // keep it alive / not optimized away

        let size = dd_swift_alloc_test_captured_size()
        var buf = [CChar](repeating: 0, count: 256)
        let len = dd_swift_alloc_test_captured_name(&buf, 256)
        let name = String(cString: buf)

        print("[Swift SQ3] captured size=\(size) bytes, name=\"\(name)\" (len=\(len))")
        XCTAssertGreaterThan(size, 0, "instance size must be recovered from the allocation")
        XCTAssertTrue(
            name.contains("Fixture"),
            "recovered type name should identify the Swift class; got \"\(name)\""
        )
    }

    // MARK: - SQ4: free-side live set (retained stay, released disappear)

    func test_sq4_free_side_live_set_tracks_retained_vs_released() {
        dd_swift_alloc_test_reset()
        // Register the fixture's Swift type metadata so only its allocations
        // are tracked (the hook is process-wide and sees everything otherwise).
        let metadata = unsafeBitCast(SQ4Fixture.self, to: UnsafeMutableRawPointer.self)
        dd_swift_alloc_test_register_class(metadata)

        // Phase A — allocate and RETAIN 10.
        var retained: [SQ4Fixture] = []
        for _ in 0..<10 { retained.append(SQ4Fixture()) }
        let aAddrs = retained.map { Unmanaged.passUnretained($0).toOpaque() }

        let afterA = dd_swift_alloc_test_live_count()
        print("[Swift SQ4] 10 retained allocated → live=\(afterA)")
        XCTAssertEqual(afterA, 10, "all retained fixtures must be live")
        for addr in aAddrs {
            XCTAssertTrue(dd_swift_alloc_test_is_live(addr), "a retained fixture must be live")
        }

        // Phase B — allocate 10 transient that are released at scope end.
        var bAddrs: [UnsafeMutableRawPointer] = []
        do {
            var transient: [SQ4Fixture] = []
            for _ in 0..<10 { transient.append(SQ4Fixture()) }
            bAddrs = transient.map { Unmanaged.passUnretained($0).toOpaque() }
            XCTAssertEqual(dd_swift_alloc_test_live_count(), 20, "10 retained + 10 transient live")
            transient.removeAll() // drop the transient group now
        }

        let afterB = dd_swift_alloc_test_live_count()
        print("[Swift SQ4] 10 transient released → live=\(afterB)")
        XCTAssertEqual(afterB, 10, "transient fixtures must be removed via swift_deallocClassInstance")
        for addr in bAddrs {
            XCTAssertFalse(dd_swift_alloc_test_is_live(addr), "a released fixture must be gone from the live set")
        }

        // Phase C — retained group is untouched.
        for addr in aAddrs {
            XCTAssertTrue(dd_swift_alloc_test_is_live(addr), "a retained fixture must still be live in phase C")
        }

        // Release the retained group.
        retained.removeAll()
        let afterC = dd_swift_alloc_test_live_count()
        print("[Swift SQ4] retained released → live=\(afterC)")
        XCTAssertEqual(afterC, 0, "all fixtures must be freed")
    }

    // MARK: - SQ5: concurrent alloc/dealloc storm (run under Thread Sanitizer)

    func test_sq5_concurrent_alloc_dealloc_storm() {
        dd_swift_alloc_test_reset()
        let metadata = unsafeBitCast(SQ5Fixture.self, to: UnsafeMutableRawPointer.self)
        dd_swift_alloc_test_register_class(metadata)

        let threads = 8
        let perThread = 10_000
        let group = DispatchGroup()

        // 8 threads churning transient pure-Swift objects: each is allocated
        // (insert into the live set) and released immediately (removed via
        // swift_deallocClassInstance), all hammering the shared guarded set.
        for _ in 0..<threads {
            DispatchQueue.global().async(group: group) {
                var sink = 0
                for _ in 0..<perThread {
                    let o = SQ5Fixture()
                    o.x = 1
                    sink &+= o.x
                }
                _ = sink
            }
        }

        // A concurrent reader snapshots the live count while the storm runs,
        // exercising read/write concurrency on the live set.
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global().async {
            for _ in 0..<2_000 { _ = dd_swift_alloc_test_live_count() }
            reader.leave()
        }

        group.wait()
        reader.wait()

        let live = dd_swift_alloc_test_live_count()
        let diag = dd_swift_alloc_hook_diagnostics()
        print("[Swift SQ5] \(threads)×\(perThread) churn → alloc=\(diag.alloc_invocations) " +
              "dealloc=\(diag.dealloc_invocations) reentrant_skips=\(diag.reentrant_skips) final_live=\(live)")

        // Every transient insert must have been matched by a remove: no leaked
        // or stale live entries after quiescence. A dropped remove or a torn
        // set operation would leave live > 0.
        XCTAssertEqual(live, 0, "no tracked objects may remain live after the storm quiesces")
        XCTAssertGreaterThanOrEqual(
            diag.alloc_invocations, UInt64(threads * perThread),
            "every churned allocation should have been observed"
        )
    }
}
#endif
