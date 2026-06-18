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
// +allocWithZone: Swizzling Spike — Tests
//
// One test per RFC-blocking question (Q1, Q2, Q3, Q4, Q7). Each test
// prints measured numbers so the findings document can quote them.
// Q5 (multi-SDK collision) and Q6 (App Store sign-off) are out of scope:
// no Crashlytics fixture is available locally, and App Store acceptance
// is only learnable post-rejection.
//
// Run on-device when possible. Simulator results are directionally
// correct for swizzle behaviour but overhead numbers must be re-measured
// on real hardware before the RFC quotes them.
// =====================================================================

// MARK: - Test fixture classes

/// Plain Obj-C class — should be intercepted via NSObject's +allocWithZone:.
@objc(DDSpikeObjCFixture) private class ObjCFixture: NSObject {
    let payload: Int
    init(payload: Int = 0) { self.payload = payload }
}

/// Swift NSObject subclass — same Obj-C runtime path, should be intercepted.
private class SwiftNSObjectFixture: NSObject {
    let payload: [Int]
    override init() { self.payload = [1, 2, 3]; super.init() }
}

/// Pure Swift class — allocated by the Swift runtime, NOT by +allocWithZone:.
/// Expected NOT to be intercepted. Documents the v1 coverage caveat.
private final class PureSwiftFixture {
    let payload: Int
    init(payload: Int = 0) { self.payload = payload }
}

/// Pattern probe for the Q2 bypass enumeration.
private struct BypassProbe {
    let label: String
    let expectedBypass: Bool
    let exercise: () -> Void
}

final class MemorySwizzlingPOCTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MemorySwizzlingPOC.stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        MemorySwizzlingPOC.stop()
        dd_memory_test_reset()
        super.tearDown()
    }

    // MARK: - Q1: Does the swizzle fire for typical allocation patterns?

    func test_q1_swizzle_fires_for_common_allocation_patterns() {
        let status = MemorySwizzlingPOC.start()
        XCTAssertEqual(status, .ok, "Swizzle must install on a clean test environment")

        // Each pattern is forced-sampled so the sampler captures the
        // instance regardless of the Poisson counter. The pass criterion
        // is that the live-set delta is non-zero for at least one pattern.
        let patterns: [(label: String, exercise: () -> Void)] = [
            ("[NSObject new]", { _ = NSObject() }),
            ("alloc + init",  { _ = ObjCFixture(payload: 1) }),
            ("Swift NSObject subclass", { _ = SwiftNSObjectFixture() }),
            ("NSMutableArray()", { _ = NSMutableArray() }),
            ("NSMutableDictionary()", { _ = NSMutableDictionary() }),
            ("NSMutableString()", { _ = NSMutableString() }),
            ("NSDate()", { _ = NSDate() }),
            ("NSUUID()", { _ = NSUUID() }),
        ]

        var firedCounts: [(String, UInt64)] = []
        for pattern in patterns {
            let liveBefore = dd_memory_test_live_count()
            dd_memory_test_force_next_sample()
            pattern.exercise()
            let liveAfter = dd_memory_test_live_count()
            firedCounts.append((pattern.label, liveAfter - liveBefore))
        }

        let diag = MemorySwizzlingPOC.diagnostics()
        print("[Spike Q1] swizzle invocations: total=\(diag.totalInvocations) observed=\(diag.observedAllocations)")
        for (label, delta) in firedCounts {
            print("[Spike Q1]   \(label) → live delta = \(delta)")
        }

        let totalDelta = firedCounts.reduce(0) { $0 + $1.1 }
        XCTAssertGreaterThan(totalDelta, 0,
                              "At least one allocation pattern must produce a tracked sample")
        XCTAssertGreaterThan(diag.totalInvocations, 0,
                              "Swizzle trampoline must have been invoked")
    }

    // MARK: - Q2: Which patterns bypass the swizzle?

    func test_q2_bypass_patterns_are_documented() {
        let status = MemorySwizzlingPOC.start()
        XCTAssertEqual(status, .ok)

        let probes: [BypassProbe] = [
            // Pure Swift classes go through swift_allocObject, not +alloc.
            BypassProbe(label: "pure Swift class", expectedBypass: true,
                        exercise: { _ = PureSwiftFixture() }),
            // Tagged pointers: NSNumber under 60-bit payload, short NSString.
            // The Obj-C runtime returns a tagged pointer without entering
            // +allocWithZone: — no instance is created.
            BypassProbe(label: "tagged NSNumber (small int)", expectedBypass: true,
                        exercise: { _ = NSNumber(value: 42) }),
            BypassProbe(label: "tagged NSString (short)", expectedBypass: true,
                        exercise: { _ = NSString(string: "hi") }),
        ]

        for probe in probes {
            let invBefore = MemorySwizzlingPOC.diagnostics().totalInvocations
            probe.exercise()
            let invAfter = MemorySwizzlingPOC.diagnostics().totalInvocations
            let didFire = invAfter > invBefore
            print("[Spike Q2]   \(probe.label) → invocations=\(invAfter - invBefore), "
                  + "expected_bypass=\(probe.expectedBypass), bypassed=\(!didFire)")
        }

        // We don't XCTAssert each one — the value is the documented list of
        // which patterns actually bypassed and which surprised us.
    }

    // MARK: - Q3: Overhead

    func test_q3_overhead_under_tight_alloc_loop() {
        let iterations = 100_000

        // Baseline: no swizzle installed.
        let baseline = measureAllocLoop(iterations: iterations)

        let status = MemorySwizzlingPOC.start()
        XCTAssertEqual(status, .ok)

        let hooked = measureAllocLoop(iterations: iterations)
        MemorySwizzlingPOC.stop()

        let overheadPercent = (hooked / baseline - 1.0) * 100.0
        let diag = MemorySwizzlingPOC.diagnostics()

        print(String(format: "[Spike Q3] Baseline: %.4fs, Swizzled: %.4fs, Overhead: %.2f%%",
                     baseline, hooked, overheadPercent))
        print("[Spike Q3] Swizzle invocations during measurement: \(diag.totalInvocations)")
        print("[Spike Q3] Observed: \(diag.observedAllocations) (passed-through after enabled-check)")

        // POC bar — flag obviously broken architecture (>200% overhead).
        // Real production target is <1% and gets there during productionization.
        XCTAssertLessThan(overheadPercent, 200.0,
                          "Swizzle overhead >200% suggests an architectural problem")
    }

    // MARK: - Q4: Reentrancy + concurrent stress

    func test_q4_concurrent_allocs_do_not_crash_or_double_track() {
        let status = MemorySwizzlingPOC.start()
        XCTAssertEqual(status, .ok)

        let threadCount = 8
        let allocsPerThread = 2_000
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "spike.q4.concurrent", attributes: .concurrent)

        for _ in 0..<threadCount {
            group.enter()
            queue.async {
                for _ in 0..<allocsPerThread {
                    _ = ObjCFixture(payload: Int.random(in: 0...1024))
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + 30)
        XCTAssertEqual(waitResult, .success, "Threads should complete within 30s")

        let diag = MemorySwizzlingPOC.diagnostics()
        let samplerDiag = MemoryProfilerPOC.diagnostics()

        print("[Spike Q4] swizzle invocations=\(diag.totalInvocations) "
              + "observed=\(diag.observedAllocations) "
              + "skipped_disabled=\(diag.skippedDisabled)")
        print("[Spike Q4] sampler total=\(samplerDiag.totalAllocations) "
              + "sampled=\(samplerDiag.sampledAllocations) "
              + "reentrant_skips=\(samplerDiag.reentrantSkips) "
              + "live=\(samplerDiag.liveSampledAllocations)")

        XCTAssertGreaterThanOrEqual(diag.totalInvocations,
                                     UInt64(threadCount * allocsPerThread),
                                     "Every allocation should have invoked the trampoline")
    }

    // MARK: - Q7: Class name + size are extractable at the swizzle point

    func test_q7_snapshot_carries_class_name_and_size() {
        let status = MemorySwizzlingPOC.start()
        XCTAssertEqual(status, .ok)

        // Force-sample one allocation per fixture class and hold a
        // reference so it stays live until snapshot capture.
        dd_memory_test_force_next_sample()
        let objc = ObjCFixture(payload: 7)

        dd_memory_test_force_next_sample()
        let swiftNs = SwiftNSObjectFixture()

        let snapshot = MemoryProfilerPOC.captureSnapshot()
        defer {
            // Keep references alive until after the snapshot read.
            _ = objc.payload
            _ = swiftNs.payload
        }

        let classNames = snapshot.samples.compactMap { $0.className }
        let sizes = snapshot.samples.map { $0.size }

        print("[Spike Q7] captured \(snapshot.samples.count) live samples")
        for sample in snapshot.samples {
            print("[Spike Q7]   class=\(sample.className ?? "<nil>") size=\(sample.size) weight=\(sample.weight)")
        }

        XCTAssertTrue(classNames.contains(where: { $0.contains("ObjCFixture") }),
                       "Obj-C fixture class name must be present in snapshot")
        XCTAssertTrue(sizes.allSatisfy { $0 > 0 },
                       "Every sample must report a non-zero size")
    }

    // MARK: - Helpers

    private func measureAllocLoop(iterations: Int) -> Double {
        let start = Date()
        for _ in 0..<iterations {
            _ = ObjCFixture(payload: 0)
        }
        return Date().timeIntervalSince(start)
    }
}

#endif
