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
// Synthetic load harness for the memory sampler (RUM-16460)
//
// Drives a known allocation stream straight into the passive sampler and
// measures what comes back out. Two properties make it usable as a
// measurement instrument rather than just another test fixture:
//
//   1. Ground truth is exact. The harness chooses every size it reports, so
//      the true allocated byte total is known to the byte and the estimator's
//      error is a real number, not an approximation of one.
//
//   2. Nothing else reaches the sampler. Allocations are reported through the
//      passive `dd_memory_observe_*` entry points with synthetic addresses, so
//      no hooks are installed and the test's own allocations (Swift arrays,
//      XCTest bookkeeping) are invisible to the measurement.
//
// The addresses are never dereferenced; they only have to be unique and
// distinguishable from the table's EMPTY/TOMBSTONE sentinels.
// =====================================================================

/// A synthetic allocation stream: `count` allocations of `size` bytes each.
internal struct SyntheticLoad {
    let size: UInt64
    let count: Int

    /// Exact byte total this load reports to the sampler — the ground truth
    /// every estimate is scored against.
    var totalBytes: UInt64 { size * UInt64(count) }

    /// Builds a load that reports approximately `bytes` in allocations of
    /// `size`. Used to express levels in the units that matter (bytes per
    /// emission window) rather than in call counts.
    static func totalling(bytes: UInt64, size: UInt64 = 64 * 1_024) -> SyntheticLoad {
        SyntheticLoad(size: size, count: Int(bytes / size))
    }
}

/// What one drained window says about the sampler's behavior under a load.
internal struct SamplerLoadMeasurement {
    /// Ground truth: bytes actually reported to the sampler.
    let trueBytes: UInt64
    /// Poisson estimate recovered from the window: the sum of size x weight.
    let estimatedBytes: Double
    /// Samples that survived into the drained window.
    let sampledCount: Int
    /// Samples lost because the window was full. Unrecoverable understatement.
    let droppedAllocRecords: UInt64
    /// Samples lost because the live table was full or collided.
    let droppedSamples: UInt64
    /// Wall time spent inside the feeding loop.
    let elapsedNanos: UInt64
    /// Calls made into the sampler, sampled and unsampled alike.
    let observedCalls: Int
    let effectiveRateBytes: UInt64
    let baseRateBytes: UInt64
    let occupancyHighWater: UInt64
    let rateWidenEvents: UInt64
    let rateNarrowEvents: UInt64

    /// Signed relative error of the estimate. Negative means the profile
    /// understates reality, which is the direction dropped samples push it.
    var relativeError: Double {
        guard trueBytes > 0 else { return 0 }
        return (estimatedBytes - Double(trueBytes)) / Double(trueBytes)
    }

    var absoluteRelativeError: Double { abs(relativeError) }

    /// Average cost of one call into the sampler. Dominated by the unsampled
    /// path, which is the fixed per-allocation cost every interception pays.
    var nanosPerCall: Double {
        observedCalls > 0 ? Double(elapsedNanos) / Double(observedCalls) : 0
    }

    var rateMultiplier: UInt64 {
        baseRateBytes > 0 ? effectiveRateBytes / baseRateBytes : 1
    }

    /// Sampling error expected from Poisson counting alone, as a fraction.
    ///
    /// Assertions are written against a multiple of this rather than a flat
    /// percentage: a flat bar is either too loose to catch bias at high sample
    /// counts or too tight to be stable at low ones, and the whole point is to
    /// distinguish real bias from variance.
    ///
    /// This is deliberately NOT `1/sqrt(n)`. That form is only valid when every
    /// sample contributes the same amount, which stops being true the moment
    /// back-pressure varies the interval inside a window: a sample drawn at
    /// 512 KB and one drawn at 128 MB differ 256-fold in the bytes they stand
    /// for, and the estimate's variance is dominated by the heavy ones. Using
    /// the naive form here understates the true error by about 2x on a window
    /// that spans several widening steps, which reads as bias in a mechanism
    /// that is in fact behaving correctly.
    ///
    /// So the error is taken from the spread of the contributions themselves,
    /// `sqrt(sum of v^2) / sum of v`. For equal contributions this collapses
    /// back to `1/sqrt(n)`; for unequal ones it is the reciprocal square root
    /// of the effective sample size.
    let oneSigmaRelativeError: Double
}

internal enum MemorySamplerLoadHarness {
    /// Synthetic addresses start well above the sentinel values and step by a
    /// cache line so the table's hash spreads them the way real allocator
    /// addresses would.
    private static let addressBase: UInt = 0x1_0000_0000
    private static let addressStride: UInt = 64

    /// Starts a clean sampler session.
    ///
    /// - Parameters:
    ///   - baseRate: configured interval in bytes.
    ///   - adaptation: when false, pins the interval to `baseRate`, which
    ///     reproduces the pre-adaptation fixed sampler exactly.
    static func start(baseRate: UInt64 = DD_MEMORY_POISSON_DEFAULT_RATE_BYTES, adaptation: Bool) {
        // Make sure no interception path is feeding the sampler in parallel:
        // a stray real allocation would corrupt the ground truth.
        ObjCAllocInterception.stop()
        dd_memory_test_reset()
        dd_memory_test_set_pressure_adaptation(adaptation)
        XCTAssertTrue(
            dd_memory_profiler_start_passive(baseRate),
            "The passive sampler must start for the load harness to measure anything"
        )
    }

    static func stop() {
        MemoryProfilerProbe.stop()
        dd_memory_test_reset()
    }

    /// Feeds one load into the sampler and returns the elapsed nanoseconds.
    ///
    /// - Parameter freeImmediately: when true each synthetic allocation is
    ///   reported freed right after it is observed, which keeps the live table
    ///   empty so the alloc window is the only source of back-pressure. Pass
    ///   false to let the live table fill instead.
    /// - Parameter startingAt: index offset so successive loads in one session
    ///   never reuse an address (a duplicate key is rejected as a drop).
    @discardableResult
    static func feed(_ load: SyntheticLoad, freeImmediately: Bool = true, startingAt offset: Int = 0) -> UInt64 {
        let started = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        for index in 0..<load.count {
            let raw = addressBase + UInt(offset + index) * addressStride
            guard let pointer = UnsafeRawPointer(bitPattern: raw) else { continue }
            dd_memory_observe_allocation_with_source(pointer, load.size, nil, DD_MEMORY_SOURCE_OBJC)
            if freeImmediately {
                dd_memory_observe_deallocation(pointer)
            }
        }
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - started
    }

    /// Drains the current window and scores it against the load that produced it.
    ///
    /// Draining is also what lets the controller relieve pressure, so a caller
    /// measuring multi-window behavior must go through here once per window.
    static func drain(after load: SyntheticLoad, elapsedNanos: UInt64) -> SamplerLoadMeasurement {
        let diagnostics = MemoryProfilerProbe.diagnostics()
        let window = MemoryProfilerProbe.captureAllocWindow()

        // Per-sample contributions to the byte estimate. Both the estimate and
        // its standard error come from this one distribution.
        let contributions = window.samples.map { Double($0.size) * $0.weight }
        let estimate = contributions.reduce(0, +)
        let sumOfSquares = contributions.reduce(0) { $0 + $1 * $1 }
        let standardError = estimate > 0 ? sumOfSquares.squareRoot() / estimate : .infinity

        return SamplerLoadMeasurement(
            trueBytes: load.totalBytes,
            estimatedBytes: estimate,
            sampledCount: window.samples.count,
            droppedAllocRecords: diagnostics.droppedAllocRecords,
            droppedSamples: diagnostics.droppedSamples,
            elapsedNanos: elapsedNanos,
            observedCalls: load.count,
            effectiveRateBytes: diagnostics.effectiveRateBytes,
            baseRateBytes: diagnostics.baseRateBytes,
            occupancyHighWater: diagnostics.occupancyHighWater,
            rateWidenEvents: diagnostics.rateWidenEvents,
            rateNarrowEvents: diagnostics.rateNarrowEvents,
            oneSigmaRelativeError: standardError
        )
    }

    /// Runs one load end to end in its own session.
    static func measure(
        _ load: SyntheticLoad,
        adaptation: Bool,
        baseRate: UInt64 = DD_MEMORY_POISSON_DEFAULT_RATE_BYTES,
        freeImmediately: Bool = true
    ) -> SamplerLoadMeasurement {
        start(baseRate: baseRate, adaptation: adaptation)
        defer { stop() }
        let elapsed = feed(load, freeImmediately: freeImmediately)
        return drain(after: load, elapsedNanos: elapsed)
    }

    /// Renders one row of the comparison table into the test log. These
    /// numbers are the deliverable of the benchmark suite, so they are printed
    /// unconditionally rather than only on failure.
    static func report(_ label: String, _ measurement: SamplerLoadMeasurement) {
        let gib = Double(measurement.trueBytes) / 1_073_741_824
        print(String(
            format: """
            [mem-sampler] %@ | truth %.2f GiB | est %+.1f%% (1sigma %.1f%%) | samples %d | dropped %d \
            | interval %llu KB (x%llu) | peak occupancy %llu | %.0f ns/call
            """,
            label,
            gib,
            measurement.relativeError * 100,
            measurement.oneSigmaRelativeError * 100,
            measurement.sampledCount,
            measurement.droppedAllocRecords,
            measurement.effectiveRateBytes / 1_024,
            measurement.rateMultiplier,
            measurement.occupancyHighWater,
            measurement.nanosPerCall
        ))
    }
}

#endif // !os(watchOS)
