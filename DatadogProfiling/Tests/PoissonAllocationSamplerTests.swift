/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import XCTest
import DatadogMachProfiler.Cxx

private typealias Sampler = dd.profiler.poisson_allocation_sampler
private let samplingInterval = Sampler.sampling_interval()
private let samplerSeed: UInt64 = 123

final class PoissonAllocationSamplerTests: XCTestCase {
    func testZeroBytesDoNotInitializeOrResetTheSession() {
        var actual = Sampler(samplerSeed)
        var expected = Sampler(samplerSeed)
        var empty = actual.sample(0, 42)
        XCTAssertEqual(empty.object_weight, 0)
        XCTAssertEqual(empty.byte_weight, 0)

        // Session token zero is valid even before the first allocation.
        let initial = actual.sample(UInt64.max, 0)
        let reference = expected.sample(UInt64.max, 0)
        XCTAssertEqual(initial.object_weight, reference.object_weight)
        XCTAssertEqual(initial.byte_weight, reference.byte_weight)
        for index in UInt64(0)..<10_000 {
            empty = actual.sample(0, index + 1)
            XCTAssertEqual(empty.object_weight, 0)
            XCTAssertEqual(empty.byte_weight, 0)
            let sample = actual.sample(256, 0)
            let comparison = expected.sample(256, 0)
            XCTAssertEqual(sample.object_weight, comparison.object_weight)
            XCTAssertEqual(sample.byte_weight, comparison.byte_weight)
        }
    }

    func testInitialSessionTokenZeroDrawsAnInterval() {
        var zeroToken = Sampler(samplerSeed)
        var otherToken = Sampler(samplerSeed)
        for _ in 0..<10_000 {
            let actual = zeroToken.sample(256, 0)
            let expected = otherToken.sample(256, 1)
            XCTAssertEqual(actual.object_weight, expected.object_weight)
            XCTAssertEqual(actual.byte_weight, expected.byte_weight)
        }
    }

    func testAllocationEndingExactlyAtTheThresholdIsSelected() {
        var oneByteAllocations = Sampler(samplerSeed)
        var threshold: UInt64 = 0
        var selected = dd.profiler.allocation_sample()
        while selected.object_weight == 0 && threshold < 20_000_000 {
            threshold += 1
            selected = oneByteAllocations.sample(1, 0)
        }
        XCTAssertGreaterThan(selected.object_weight, 0)
        XCTAssertGreaterThan(threshold, 1)
        guard selected.object_weight > 0, threshold > 1 else {
            return
        }

        var boundary = Sampler(samplerSeed)
        let before = boundary.sample(threshold - 1, 0)
        XCTAssertEqual(before.object_weight, 0)
        XCTAssertEqual(before.byte_weight, 0)
        let at = boundary.sample(1, 0)
        XCTAssertEqual(at.object_weight, selected.object_weight)
        XCTAssertEqual(at.byte_weight, selected.byte_weight)
        XCTAssertEqual(at.object_weight, 524_288.5000001589, accuracy: 0.000001)
        XCTAssertEqual(at.byte_weight, at.object_weight)
    }

    func testUnsignedMaximumAllocationIsSelectedWithoutOverflow() {
        var sampler = Sampler(samplerSeed)
        let sample = sampler.sample(UInt64.max, 0)
        XCTAssertEqual(sample.object_weight, 1)
        XCTAssertEqual(sample.byte_weight, Double(UInt64.max))
        XCTAssertTrue(sample.byte_weight.isFinite)
    }

    func testMinimumIntervalSelectsTheFirstPositiveAllocation() {
        // The largest open-interval uniform draw produces a one-byte countdown.
        var sampler = Sampler(3_558_559_446_808_474_027)
        let selected = sampler.sample(1, 0)
        XCTAssertGreaterThan(selected.object_weight, 0)
        XCTAssertTrue(selected.object_weight.isFinite)
        XCTAssertTrue(selected.byte_weight.isFinite)
        XCTAssertEqual(selected.object_weight, 524_288.5000001589, accuracy: 0.000001)
        XCTAssertEqual(selected.byte_weight, selected.object_weight)
    }

    func testMaximumIntervalIsFiniteAndSelectsAtItsBoundary() {
        // The smallest open-interval uniform draw produces this maximum countdown.
        var sampler = Sampler(7_046_029_254_386_353_131)
        let before = sampler.sample(19_260_664 - 1, 0)
        XCTAssertEqual(before.object_weight, 0)
        XCTAssertEqual(before.byte_weight, 0)
        let selected = sampler.sample(1, 0)
        XCTAssertGreaterThan(selected.object_weight, 0)
        XCTAssertTrue(selected.object_weight.isFinite)
        XCTAssertTrue(selected.byte_weight.isFinite)
        XCTAssertEqual(selected.object_weight, 524_288.5000001589, accuracy: 0.000001)
        XCTAssertEqual(selected.byte_weight, selected.object_weight)
    }

    func testDefaultConstructorSamplesAnUnsignedMaximumAllocation() {
        var sampler = Sampler()
        let sample = sampler.sample(UInt64.max, 0)
        XCTAssertEqual(sample.object_weight, 1)
        XCTAssertEqual(sample.byte_weight, Double(UInt64.max))
        XCTAssertTrue(sample.byte_weight.isFinite)
    }

    func testLargeAllocationRearmsOnceFromItsEnd() {
        var actual = Sampler(samplerSeed)
        var expected = Sampler(samplerSeed)
        let first = actual.sample(UInt64.max, 0)
        let comparison = expected.sample(UInt64.max / 2, 0)
        XCTAssertEqual(first.object_weight, 1)
        XCTAssertEqual(comparison.object_weight, 1)

        // Overshoot must not change the next countdown or consume additional random draws.
        for _ in 0..<10_000 {
            let sample = actual.sample(256, 0)
            let comparison = expected.sample(256, 0)
            XCTAssertEqual(sample.object_weight, comparison.object_weight)
            XCTAssertEqual(sample.byte_weight, comparison.byte_weight)
        }
    }

    func testSessionChangeDiscardsTheCountdownWithoutReseeding() {
        var changedSession = Sampler(samplerSeed)
        var continuousSession = Sampler(samplerSeed)
        _ = changedSession.sample(UInt64.max, 0)
        _ = continuousSession.sample(UInt64.max, 0)
        _ = continuousSession.sample(UInt64.max, 0)

        // Both now use the third draw: resetting discards the second draw, without reseeding.
        var selected = 0
        for _ in 0..<10_000 {
            let actual = changedSession.sample(256, 1)
            let expected = continuousSession.sample(256, 0)
            XCTAssertEqual(actual.object_weight, expected.object_weight)
            XCTAssertEqual(actual.byte_weight, expected.byte_weight)
            selected += actual.object_weight == 0 ? 0 : 1
        }
        XCTAssertGreaterThan(selected, 0)
    }

    func testMovingPartiallyConsumedSamplerPreservesItsState() {
        var original = Sampler(samplerSeed)
        var control = Sampler(samplerSeed)
        let prefix = original.sample(4_096, 0)
        let reference = control.sample(4_096, 0)
        XCTAssertEqual(prefix.object_weight, 0)
        XCTAssertEqual(prefix.byte_weight, 0)
        XCTAssertEqual(reference.object_weight, 0)
        XCTAssertEqual(reference.byte_weight, 0)

        var moved = consume original
        var selected = 0
        for _ in 0..<10_000 {
            let actual = moved.sample(256, 0)
            let expected = control.sample(256, 0)
            XCTAssertEqual(actual.object_weight, expected.object_weight)
            XCTAssertEqual(actual.byte_weight, expected.byte_weight)
            selected += actual.object_weight == 0 ? 0 : 1
        }
        XCTAssertGreaterThan(selected, 0)
    }

    func testWeightsAreIndependentAndRemainFractionalUntilAccumulated() {
        var sampler = Sampler(samplerSeed)
        let probability = 0.6321205588285577 // 1 - exp(-1)
        let expectedObjectWeight = 1.5819767068693265
        var objects = 0.0
        var bytes = 0.0
        var selected = 0
        for _ in 0..<100 {
            let sample = sampler.sample(samplingInterval, 0)
            if sample.object_weight == 0 {
                XCTAssertEqual(sample.byte_weight, 0)
                continue
            }
            XCTAssertEqual(sample.object_weight, expectedObjectWeight, accuracy: 0.000000000001)
            XCTAssertEqual(sample.byte_weight, Double(samplingInterval) / probability, accuracy: 0.000001)
            objects += sample.object_weight
            bytes += sample.byte_weight
            selected += 1
        }
        XCTAssertGreaterThan(selected, 0)
        XCTAssertEqual(objects, Double(selected) * expectedObjectWeight, accuracy: 0.000000001)
        XCTAssertEqual(bytes, Double(selected) * Double(samplingInterval) / probability, accuracy: 0.001)
        XCTAssertNotEqual(objects.rounded(), Double(selected) * expectedObjectWeight.rounded())
    }

    func testFixedSeedInclusionAndWeightedTotalsAcrossAllocationSizes() {
        let sizes: [UInt64] = [64, 4_096, samplingInterval, 8 * samplingInterval]
        for size in sizes {
            var sampler = Sampler(samplerSeed)
            let count = size == 64 ? 2_000_000 : 100_000
            var totals = SamplingTotals()
            for _ in 0..<count {
                totals.add(sampler.sample(size, 0))
            }

            // Calculate the oracle independently of the sampler's numerically stable implementation.
            let probability = 1 - exp(-Double(size) / Double(samplingInterval))
            let selectionDeviation = sqrt(Double(count) * probability * (1 - probability))
            let objectDeviation = sqrt(Double(count) * (1 - probability) / probability)
            XCTAssertEqual(
                Double(totals.selected),
                Double(count) * probability,
                accuracy: 6 * selectionDeviation + 1,
                "size = \(size)"
            )
            XCTAssertEqual(totals.objects, Double(count), accuracy: 6 * objectDeviation + 1, "size = \(size)")
            XCTAssertEqual(
                totals.bytes,
                Double(count) * Double(size),
                accuracy: (6 * objectDeviation + 1) * Double(size),
                "size = \(size)"
            )
        }
    }

    func testConditionalSelectionProbabilityAfterAnUnsampledPrefix() {
        let prefixes = [samplingInterval / 8, samplingInterval, 2 * samplingInterval]
        let probeSize: UInt64 = 4_096
        let probability = 1 - exp(-Double(probeSize) / Double(samplingInterval))
        for prefix in prefixes {
            var sampler = Sampler(samplerSeed)
            var survivors = 0
            var selected = 0
            for session in UInt64(0)..<100_000 {
                if sampler.sample(prefix, session).object_weight == 0 {
                    survivors += 1
                    selected += sampler.sample(probeSize, session).object_weight == 0 ? 0 : 1
                }
            }

            // Condition on survival: the remaining countdown still has the same exponential law.
            XCTAssertGreaterThan(survivors, 0)
            let deviation = sqrt(Double(survivors) * probability * (1 - probability))
            XCTAssertEqual(
                Double(selected),
                Double(survivors) * probability,
                accuracy: 6 * deviation + 1,
                "prefix = \(prefix), survivors = \(survivors)"
            )
        }
    }

    func testMixedAllocationSizesEstimateBothObjectAndByteTotals() {
        var sampler = Sampler(samplerSeed)
        let sizes: [UInt64] = [64, 4_096, samplingInterval, 8 * samplingInterval]
        let countPerSize = 100_000
        var totals = SamplingTotals()
        var expectedObjects = 0.0
        var expectedBytes = 0.0
        var objectVariance = 0.0
        var byteVariance = 0.0
        for size in sizes {
            let probability = 1 - exp(-Double(size) / Double(samplingInterval))
            let variance = Double(countPerSize) * (1 - probability) / probability
            expectedObjects += Double(countPerSize)
            expectedBytes += Double(countPerSize) * Double(size)
            objectVariance += variance
            byteVariance += variance * Double(size) * Double(size)
        }
        for _ in 0..<countPerSize {
            for size in sizes {
                totals.add(sampler.sample(size, 0))
            }
        }
        XCTAssertEqual(totals.objects, expectedObjects, accuracy: 6 * sqrt(objectVariance))
        XCTAssertEqual(totals.bytes, expectedBytes, accuracy: 6 * sqrt(byteVariance))
    }

    func testConcurrentThreadsHaveIndependentSamplerState() {
        var baselineSampler = Sampler(samplerSeed)
        let baseline = sampleWorkload(&baselineSampler)
        let results = SamplingResults()
        let finished = DispatchGroup()
        let threads = (0..<8).map { _ in
            finished.enter()
            return Thread {
                var sampler = Sampler(samplerSeed)
                results.append(sampleWorkload(&sampler))
                finished.leave()
            }
        }
        for thread in threads {
            thread.start()
        }

        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)
        let completed = results.snapshot()
        XCTAssertEqual(completed.count, threads.count)
        for result in completed {
            XCTAssertEqual(result, baseline)
        }
    }
}

private struct SamplingTotals: Equatable, Sendable {
    var selected = 0
    var objects = 0.0
    var bytes = 0.0

    mutating func add(_ sample: dd.profiler.allocation_sample) {
        selected += sample.object_weight == 0 ? 0 : 1
        objects += sample.object_weight
        bytes += sample.byte_weight
    }
}

private func sampleWorkload(_ sampler: inout Sampler) -> SamplingTotals {
    var totals = SamplingTotals()
    let sizes: [UInt64] = [64, 4_096, samplingInterval, 8 * samplingInterval]
    for index in UInt64(0)..<200_000 {
        totals.add(sampler.sample(sizes[Int(index % UInt64(sizes.count))], index / 50_000))
    }
    return totals
}

private final class SamplingResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SamplingTotals] = []

    func append(_ totals: SamplingTotals) {
        lock.lock()
        values.append(totals)
        lock.unlock()
    }

    func snapshot() -> [SamplingTotals] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
#endif // !os(watchOS)
