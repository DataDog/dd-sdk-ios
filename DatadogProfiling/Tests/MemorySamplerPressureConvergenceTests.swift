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
// Layer 2 — controller convergence and anti-ratchet (RUM-16460)
//
// Layer 1 measures single windows in isolation. This suite is about the
// controller's behavior over a *sequence* of windows, which is where a
// feedback loop actually fails:
//
//   - it never engages, and the window saturates anyway;
//   - it engages and never disengages, permanently degrading resolution long
//     after the burst that caused it (the ratchet);
//   - it engages and disengages every window, oscillating and halving useful
//     resolution for nothing;
//   - it holds the totals unbiased on average while getting individual phases
//     badly wrong.
//
// These are the acceptance gates for shipping the mechanism unflagged. They
// are correctness assertions, not benchmarks: none of them depends on timing.
//
// The adaptive branch of the libdatadog experiment that prompted this work
// fails the third and fourth of these by construction — its controller is
// sign-inverted, so load makes it sample harder — which is why "it converges"
// is worth pinning rather than assuming.
// =====================================================================

final class MemorySamplerPressureConvergenceTests: XCTestCase {
    /// Volume that leaves the window at ~25% at the base rate: comfortably
    /// inside the hysteresis band's lower edge, so it neither widens nor is
    /// mistaken for pressure.
    private static let quietWindow = SyntheticLoad.totalling(bytes: 512 * 1_024 * 1_024)

    /// Volume that would need ~16,384 window entries at the base rate — 4x
    /// capacity — and therefore forces the controller to engage hard.
    private static let burstWindow = SyntheticLoad.totalling(bytes: 8 * 1_073_741_824)

    /// Volume heavy enough to widen the interval, but which then lands between
    /// the relief (30%) and step (50%) marks once widened — the controller's
    /// intended resting state under sustained load.
    ///
    /// The level matters: a lighter load would settle trivially at the base
    /// rate and prove nothing about hysteresis, since a controller with no
    /// dead band at all would also hold still there. 3 GiB per window has to
    /// widen, then find a non-trivial fixed point and stay on it.
    private static let moderateWindow = SyntheticLoad.totalling(bytes: 3 * 1_073_741_824)

    private var addressOffset = 0

    override func setUp() {
        super.setUp()
        ObjCAllocInterception.stop()
        dd_memory_test_reset()
        addressOffset = 0
        MemorySamplerLoadHarness.start(adaptation: true)
    }

    override func tearDown() {
        MemorySamplerLoadHarness.stop()
        super.tearDown()
    }

    /// Feeds one load and drains the window, keeping synthetic addresses
    /// unique across the whole session so a repeat address is never mistaken
    /// for a duplicate-key drop.
    @discardableResult
    private func runWindow(_ load: SyntheticLoad) -> SamplerLoadMeasurement {
        let elapsed = MemorySamplerLoadHarness.feed(load, startingAt: addressOffset)
        addressOffset += load.count
        return MemorySamplerLoadHarness.drain(after: load, elapsedNanos: elapsed)
    }

    // MARK: - Engagement

    /// Light load must leave the sampler exactly where it is. A controller
    /// that drifts under normal conditions would degrade every profile the
    /// SDK ever emits, which is a far worse outcome than the saturation it
    /// was built to prevent.
    func testLightLoadNeverLeavesTheBaseRate() {
        for window in 1...5 {
            let measurement = runWindow(Self.quietWindow)
            XCTAssertEqual(
                measurement.rateMultiplier, 1,
                "Window \(window): light load must not widen the interval"
            )
            XCTAssertEqual(
                measurement.effectiveRateBytes, DD_MEMORY_POISSON_DEFAULT_RATE_BYTES,
                "Window \(window): the interval must remain the configured 512 KB"
            )
        }

        let diagnostics = MemoryProfilerProbe.diagnostics()
        XCTAssertEqual(diagnostics.rateWidenEvents, 0, "No widening should have occurred at all")
        XCTAssertEqual(diagnostics.droppedAllocRecords, 0, "Light load must not drop records")
    }

    /// The engagement case: a burst that would overrun the window four times
    /// over must widen instead of dropping.
    func testBurstWidensIntervalInsteadOfDroppingRecords() {
        let measurement = runWindow(Self.burstWindow)
        MemorySamplerLoadHarness.report("burst", measurement)

        XCTAssertGreaterThan(
            measurement.rateMultiplier, 1,
            "A 4x-capacity burst must engage back-pressure"
        )
        XCTAssertEqual(
            measurement.droppedAllocRecords, 0,
            "Widening must happen early enough that no record is ever dropped"
        )
        XCTAssertLessThanOrEqual(
            measurement.occupancyHighWater, 4_096,
            "Occupancy must never exceed the window capacity"
        )

        let bound = max(4 * measurement.oneSigmaRelativeError, 0.02)
        XCTAssertLessThan(
            measurement.absoluteRelativeError, bound,
            "The burst window's own estimate must stay unbiased, not just the session total"
        )
    }

    // MARK: - Recovery

    /// The ratchet test. After the burst drains, quiet windows must walk the
    /// interval back to the base rate monotonically and within a bounded
    /// number of windows.
    ///
    /// Recovery is deliberately one step per window rather than an immediate
    /// reset, so a burst that is only pausing does not instantly re-saturate.
    /// The cost of that choice is bounded here: if it ever takes more windows
    /// than this, resolution stays degraded long after the cause has passed
    /// and the ceiling or the step size needs revisiting.
    func testIntervalReturnsToBaseRateAfterBurst() {
        let burst = runWindow(Self.burstWindow)
        let peakMultiplier = burst.rateMultiplier
        XCTAssertGreaterThan(peakMultiplier, 1, "The burst must have widened the interval first")

        var multipliers: [UInt64] = [peakMultiplier]
        var windowsToRecover: Int?

        for window in 1...12 {
            let measurement = runWindow(Self.quietWindow)
            multipliers.append(measurement.rateMultiplier)

            if measurement.rateMultiplier == 1, windowsToRecover == nil {
                windowsToRecover = window
                break
            }
        }

        print("[mem-sampler] recovery multipliers: \(multipliers.map(String.init).joined(separator: " -> "))")

        // Monotone descent: a controller that overshoots back up while the
        // load is quiet is oscillating, not recovering.
        for (previous, next) in zip(multipliers, multipliers.dropFirst()) {
            XCTAssertLessThanOrEqual(
                next, previous,
                "The multiplier must never increase while load is quiet — sequence \(multipliers)"
            )
        }

        let recovered = try? XCTUnwrap(windowsToRecover)
        XCTAssertNotNil(
            recovered,
            "The interval never returned to the base rate — this is the ratchet failure mode"
        )
        if let recovered {
            XCTAssertLessThanOrEqual(
                recovered, 9,
                """
                Recovery took \(recovered) quiet windows from x\(peakMultiplier). At one halving per \
                window the ceiling bounds this at 8; more means relief is being skipped.
                """
            )
        }
    }

    /// Sustained moderate load must find a fixed point inside the hysteresis
    /// band and stay there. Without the gap between the 30% relief mark and
    /// the 50% step mark, this workload would widen, empty the next window,
    /// narrow, refill, and oscillate forever — throwing away half the
    /// resolution on alternating windows for no benefit.
    func testSustainedModerateLoadSettlesWithoutOscillating() {
        var multipliers: [UInt64] = []
        for _ in 1...8 {
            multipliers.append(runWindow(Self.moderateWindow).rateMultiplier)
        }

        print("[mem-sampler] steady-state multipliers: \(multipliers.map(String.init).joined(separator: " -> "))")

        // The controller is allowed to hunt while it converges; what it may
        // not do is keep hunting. The tail must be a single repeated value.
        let tail = multipliers.suffix(3)
        XCTAssertEqual(
            Set(tail).count, 1,
            "Steady load must converge to a fixed multiplier; instead it kept cycling: \(multipliers)"
        )

        // And that fixed point must be a widened one. Settling at the base
        // rate would mean this load never engaged the controller, in which
        // case the test says nothing about the dead band that prevents
        // oscillation between widened states.
        XCTAssertGreaterThan(
            tail.first ?? 1, 1,
            "This load must settle at a widened interval for the test to exercise hysteresis"
        )

        let diagnostics = MemoryProfilerProbe.diagnostics()
        XCTAssertEqual(diagnostics.droppedAllocRecords, 0, "Moderate load must never drop records")
    }

    /// Alternating burst and quiet is the adversarial shape for a controller
    /// with hysteresis: it is exactly the pattern that can push it into
    /// resonance, engaging on every burst and relieving on every lull with the
    /// worst possible phase.
    ///
    /// The requirement is not that the multiplier stays constant — it should
    /// move, that is the point — but that no window ever drops a record and
    /// every window's estimate stays inside sampling noise.
    func testSawtoothLoadNeverDropsRecordsInAnyPhase() {
        for cycle in 1...3 {
            for (name, load) in [("burst", Self.burstWindow), ("quiet", Self.quietWindow)] {
                let measurement = runWindow(load)

                XCTAssertEqual(
                    measurement.droppedAllocRecords, 0,
                    "Cycle \(cycle) \(name): a sawtooth must not saturate the window in any phase"
                )

                let bound = max(4 * measurement.oneSigmaRelativeError, 0.02)
                XCTAssertLessThan(
                    measurement.absoluteRelativeError, bound,
                    """
                    Cycle \(cycle) \(name): estimate off by \
                    \(String(format: "%.1f%%", measurement.relativeError * 100)) against a \
                    \(String(format: "%.1f%%", bound * 100)) bound. Per-phase accuracy is the \
                    requirement; a session total that averages out is not sufficient.
                    """
                )
            }
        }
    }

    // MARK: - Estimator integrity across an interval change

    /// The correctness property the whole mechanism rests on: a sample's
    /// weight must reflect the interval that governed its own selection, not
    /// whatever the interval happens to be when it fires.
    ///
    /// Those are the same number under a fixed rate, so nothing in the
    /// pre-adaptation suite covers the difference. Under back-pressure a
    /// countdown drawn at 512 KB can fire after the interval has moved to
    /// 8 MB; weighting it at 8 MB would overstate that sample sixteenfold. A
    /// window spanning several widening steps is the only place that
    /// mismatch becomes visible, and it shows up as inflation, not noise.
    func testWeightsTrackTheIntervalEachSampleWasDrawnUnder() {
        let measurement = runWindow(Self.burstWindow)

        XCTAssertGreaterThan(
            measurement.rateWidenEvents, 1,
            "This test is only meaningful if the interval changed several times mid-window"
        )

        let bound = max(4 * measurement.oneSigmaRelativeError, 0.02)
        XCTAssertLessThan(
            measurement.absoluteRelativeError, bound,
            """
            Estimate off by \(String(format: "%.1f%%", measurement.relativeError * 100)) across \
            \(measurement.rateWidenEvents) interval changes. A large positive error here means \
            weights are being taken from the post-change interval rather than the drawing one.
            """
        )

        // Directional check: the specific bug inflates rather than deflates,
        // so an overshoot well past the noise band is called out separately
        // from a generic accuracy failure.
        XCTAssertLessThan(
            measurement.relativeError, bound,
            "A large positive bias across interval changes is the weight-mismatch signature"
        )
    }
}

#endif // !os(watchOS)
