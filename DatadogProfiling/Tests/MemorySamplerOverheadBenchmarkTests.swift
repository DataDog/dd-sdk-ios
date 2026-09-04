/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import Foundation
import XCTest
import DatadogMachProfiler
import DatadogMachProfiler.Testing
@testable import DatadogProfiling

// =====================================================================
// Layer 1 — sampler cost and accuracy under a load sweep (RUM-16460)
//
// This suite exists to answer whether occupancy-driven back-pressure is worth
// shipping, and the metric of merit is NOT CPU. Widening the interval can only
// ever remove work: the unsampled path is untouched and fewer samples means
// fewer backtraces. A CPU comparison reads flat-to-better and settles nothing.
//
// What the mechanism can get wrong is accuracy. So the headline measurement is
// the estimator's error against a ground truth the harness knows exactly, swept
// across allocation volumes that span two orders of magnitude — from well
// inside the fixed-capacity structures to far past them. Cost is measured too,
// as a guardrail against the change quietly making the hot path worse.
//
// Assertions are written against multiples of the Poisson standard error
// rather than flat percentages; see `oneSigmaRelativeError`.
// =====================================================================

final class MemorySamplerOverheadBenchmarkTests: XCTestCase {
    /// Sampled-count multiples of the 4096-entry window capacity that the
    /// sweep visits, expressed as the allocation volume that produces them at
    /// the 512 KB base rate.
    ///
    /// - 0.5 GiB stays at a quarter of capacity: nothing adapts, and both
    ///   configurations must agree. This is the control.
    /// - 2 GiB exactly fills the window at the base rate.
    /// - 8 GiB and 32 GiB overrun it by 4x and 16x. 32 GiB over a 60s emission
    ///   window is ~550 MB/s of sustained allocation: high, but a real number
    ///   for a pathological client, and precisely the case the RFC thread was
    ///   about.
    private static let sweepGibibytes: [Double] = [0.5, 2, 8, 32]

    private static func load(gibibytes: Double) -> SyntheticLoad {
        SyntheticLoad.totalling(bytes: UInt64(gibibytes * 1_073_741_824))
    }

    override func setUp() {
        super.setUp()
        ObjCAllocInterception.stop()
        dd_memory_test_reset()
    }

    override func tearDown() {
        MemorySamplerLoadHarness.stop()
        super.tearDown()
    }

    // MARK: - Accuracy

    /// The headline comparison: same workload, both configurations, scored
    /// against ground truth.
    ///
    /// The fixed sampler is expected to be accurate right up until the window
    /// fills and then to fall off a cliff, because a dropped sample takes its
    /// weight with it and nothing downstream can tell that it existed. The
    /// adaptive sampler is expected to hold its error inside sampling noise at
    /// every level, having traded resolution for coverage instead.
    func testEstimatorAccuracyAcrossLoadSweep() {
        var fixedErrors: [Double] = []
        var adaptiveErrors: [Double] = []

        for gibibytes in Self.sweepGibibytes {
            let load = Self.load(gibibytes: gibibytes)

            let fixed = MemorySamplerLoadHarness.measure(load, adaptation: false)
            MemorySamplerLoadHarness.report(String(format: "fixed    %5.1f GiB", gibibytes), fixed)
            fixedErrors.append(fixed.relativeError)

            let adaptive = MemorySamplerLoadHarness.measure(load, adaptation: true)
            MemorySamplerLoadHarness.report(String(format: "adaptive %5.1f GiB", gibibytes), adaptive)
            adaptiveErrors.append(adaptive.relativeError)

            // Adaptation must never let the window saturate; that is the whole
            // job. A single dropped record is a failure of the mechanism, not
            // a tolerance to be widened.
            XCTAssertEqual(
                adaptive.droppedAllocRecords, 0,
                "Back-pressure must widen the interval before the window fills (at \(gibibytes) GiB)"
            )

            // 4 sigma, with a floor so the very largest sample counts are not
            // held to a tolerance tighter than the arithmetic warrants.
            let bound = max(4 * adaptive.oneSigmaRelativeError, 0.02)
            XCTAssertLessThan(
                adaptive.absoluteRelativeError, bound,
                """
                Adaptive estimate at \(gibibytes) GiB was off by \
                \(String(format: "%.1f%%", adaptive.relativeError * 100)), outside the \
                \(String(format: "%.1f%%", bound * 100)) sampling-noise bound over \
                \(adaptive.sampledCount) samples. An error this large is bias, not variance.
                """
            )
        }

        // The control level must agree between configurations: below the
        // pressure threshold, adaptation is inert and the two are the same
        // sampler. If this drifts, the controller is firing when it should not.
        XCTAssertLessThan(
            abs(fixedErrors[0] - adaptiveErrors[0]), 0.15,
            "Below the pressure threshold both configurations must behave identically"
        )

        // And the motivating failure must actually be present at the top of
        // the sweep, otherwise this suite is not measuring anything.
        XCTAssertLessThan(
            fixedErrors[fixedErrors.count - 1], -0.5,
            """
            The fixed sampler was expected to understate the heaviest load by more than half \
            once the window saturates. It did not, which means the sweep no longer reaches \
            saturation and the levels need revisiting.
            """
        )
    }

    /// Every sample the fixed sampler drops is understatement that no consumer
    /// can detect or correct. This pins the size of that gap at the top of the
    /// sweep so the comparison above has a stated baseline.
    func testFixedIntervalDropsRecordsOnceWindowSaturates() {
        let load = Self.load(gibibytes: 8)
        let fixed = MemorySamplerLoadHarness.measure(load, adaptation: false)
        MemorySamplerLoadHarness.report("fixed saturation", fixed)

        XCTAssertGreaterThan(
            fixed.droppedAllocRecords, 0,
            "8 GiB at the 512 KB base rate must overrun the 4096-entry window"
        )
        XCTAssertLessThan(
            fixed.relativeError, -0.5,
            "Dropped records must show up as understatement, which is the defect being fixed"
        )
    }

    // MARK: - Cost

    /// Guardrail, not a headline. Adaptation adds one comparison per *sample*
    /// — never per allocation — so the per-call cost that dominates the
    /// Objective-C interception path must be indistinguishable between the two
    /// configurations.
    ///
    /// The bound is deliberately loose. This runs on shared CI hardware where
    /// a 2x swing between runs is ordinary; the assertion is here to catch a
    /// structural regression (an atomic added to the hot path, a lock taken
    /// per allocation), not to police noise. The printed numbers are the
    /// useful output.
    func testPerAllocationCostIsUnaffectedByAdaptation() {
        // Warm up: first-touch page faults on the mmap'd table would otherwise
        // land entirely on whichever configuration runs first.
        _ = MemorySamplerLoadHarness.measure(Self.load(gibibytes: 0.25), adaptation: true)

        let load = Self.load(gibibytes: 2)
        let fixed = MemorySamplerLoadHarness.measure(load, adaptation: false)
        let adaptive = MemorySamplerLoadHarness.measure(load, adaptation: true)

        MemorySamplerLoadHarness.report("cost fixed   ", fixed)
        MemorySamplerLoadHarness.report("cost adaptive", adaptive)

        XCTAssertGreaterThan(fixed.nanosPerCall, 0, "Timing must have been captured")
        XCTAssertLessThan(
            adaptive.nanosPerCall, fixed.nanosPerCall * 2.5,
            """
            Adaptive per-call cost (\(String(format: "%.0f", adaptive.nanosPerCall)) ns) is far above \
            fixed (\(String(format: "%.0f", fixed.nanosPerCall)) ns). Adaptation touches only the \
            sampled slow path, so a gap this size means work leaked onto the per-allocation path.
            """
        )
    }

    /// The reason the adaptive configuration is also *cheaper* under load: it
    /// stops paying for backtraces it is only going to throw away. At a
    /// saturating level the fixed sampler unwinds a stack for every sampled
    /// allocation and then discards most of them at a full window.
    func testAdaptationAvoidsBacktraceWorkItWouldDiscard() {
        let load = Self.load(gibibytes: 8)

        let fixed = MemorySamplerLoadHarness.measure(load, adaptation: false)
        let adaptive = MemorySamplerLoadHarness.measure(load, adaptation: true)

        let fixedAttempted = fixed.sampledCount + Int(fixed.droppedAllocRecords)
        let adaptiveAttempted = adaptive.sampledCount + Int(adaptive.droppedAllocRecords)

        print("[mem-sampler] backtraces attempted — fixed \(fixedAttempted), adaptive \(adaptiveAttempted)")

        XCTAssertLessThan(
            adaptiveAttempted, fixedAttempted,
            "Widening under pressure must reduce the number of stacks unwound, not increase it"
        )
    }
}

#endif // !os(watchOS)
