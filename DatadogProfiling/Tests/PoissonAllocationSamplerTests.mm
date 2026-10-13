/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <XCTest/XCTest.h>

#include <TargetConditionals.h>

#if !TARGET_OS_WATCH

#include "poisson_allocation_sampler.h"

#include <array>
#include <cmath>
#include <limits>
#include <thread>

using dd::profiler::allocation_sample;
using dd::profiler::poisson_allocation_sampler;

namespace {

constexpr uint64_t interval = poisson_allocation_sampler::sampling_interval_bytes;
constexpr uint64_t seed = 123;

struct sampling_totals {
    uint64_t selected = 0;
    double objects = 0;
    double bytes = 0;

    void add(allocation_sample sample) {
        selected += sample.object_weight != 0;
        objects += sample.object_weight;
        bytes += sample.byte_weight;
    }
};

sampling_totals sample_workload(poisson_allocation_sampler &sampler) {
    sampling_totals totals;
    constexpr std::array<uint64_t, 4> sizes = {64, 4096, interval, 8 * interval};
    for (uint64_t index = 0; index < 200000; ++index) {
        totals.add(sampler.sample(sizes[index % sizes.size()], index / 50000));
    }
    return totals;
}

} // namespace

@interface PoissonAllocationSamplerTests : XCTestCase
@end

@implementation PoissonAllocationSamplerTests

- (void)testSamplingIntervalIs512KiB {
    XCTAssertEqual(interval, 512ULL * 1024ULL);
}

- (void)testZeroBytesDoNotInitializeOrResetTheSession {
    poisson_allocation_sampler actual(seed);
    poisson_allocation_sampler expected(seed);
    allocation_sample empty = actual.sample(0, 42);
    XCTAssertEqual(empty.object_weight, 0);
    XCTAssertEqual(empty.byte_weight, 0);

    // Session token zero is valid even before the first allocation.
    allocation_sample initial = actual.sample(std::numeric_limits<uint64_t>::max(), 0);
    allocation_sample reference = expected.sample(std::numeric_limits<uint64_t>::max(), 0);
    XCTAssertEqual(initial.object_weight, reference.object_weight);
    XCTAssertEqual(initial.byte_weight, reference.byte_weight);
    for (uint64_t index = 0; index < 10000; ++index) {
        empty = actual.sample(0, index + 1);
        XCTAssertEqual(empty.object_weight, 0);
        XCTAssertEqual(empty.byte_weight, 0);
        allocation_sample sample = actual.sample(256, 0);
        allocation_sample comparison = expected.sample(256, 0);
        XCTAssertEqual(sample.object_weight, comparison.object_weight);
        XCTAssertEqual(sample.byte_weight, comparison.byte_weight);
    }
}

- (void)testInitialSessionTokenZeroDrawsAnInterval {
    poisson_allocation_sampler zeroToken(seed);
    poisson_allocation_sampler otherToken(seed);
    for (uint64_t index = 0; index < 10000; ++index) {
        allocation_sample actual = zeroToken.sample(256, 0);
        allocation_sample expected = otherToken.sample(256, 1);
        XCTAssertEqual(actual.object_weight, expected.object_weight);
        XCTAssertEqual(actual.byte_weight, expected.byte_weight);
    }
}

- (void)testAllocationEndingExactlyAtTheThresholdIsSelected {
    poisson_allocation_sampler oneByteAllocations(seed);
    uint64_t threshold = 0;
    allocation_sample selected = {0, 0};
    while (selected.object_weight == 0 && threshold < 20000000) {
        ++threshold;
        selected = oneByteAllocations.sample(1, 0);
    }
    XCTAssertGreaterThan(selected.object_weight, 0);
    XCTAssertGreaterThan(threshold, 1ULL);
    if (selected.object_weight == 0 || threshold <= 1) {
        return;
    }

    poisson_allocation_sampler boundary(seed);
    allocation_sample before = boundary.sample(threshold - 1, 0);
    XCTAssertEqual(before.object_weight, 0);
    XCTAssertEqual(before.byte_weight, 0);
    allocation_sample at = boundary.sample(1, 0);
    XCTAssertEqual(at.object_weight, selected.object_weight);
    XCTAssertEqual(at.byte_weight, selected.byte_weight);
    XCTAssertEqualWithAccuracy(at.object_weight, 524288.5000001589, 0.000001);
    XCTAssertEqual(at.byte_weight, at.object_weight);
}

- (void)testUnsignedMaximumAllocationIsSelectedWithoutOverflow {
    poisson_allocation_sampler sampler(seed);
    uint64_t size = std::numeric_limits<uint64_t>::max();
    allocation_sample sample = sampler.sample(size, 0);
    XCTAssertEqual(sample.object_weight, 1);
    XCTAssertEqual(sample.byte_weight, static_cast<double>(size));
    XCTAssertTrue(std::isfinite(sample.byte_weight));
}

- (void)testMinimumIntervalSelectsTheFirstPositiveAllocation {
    // The largest open-interval uniform draw produces a one-byte countdown.
    poisson_allocation_sampler sampler(3558559446808474027ULL);
    allocation_sample selected = sampler.sample(1, 0);
    XCTAssertGreaterThan(selected.object_weight, 0.0);
    XCTAssertTrue(std::isfinite(selected.object_weight));
    XCTAssertTrue(std::isfinite(selected.byte_weight));
    XCTAssertEqualWithAccuracy(selected.object_weight, 524288.5000001589, 0.000001);
    XCTAssertEqual(selected.byte_weight, selected.object_weight);
}

- (void)testMaximumIntervalIsFiniteAndSelectsAtItsBoundary {
    // The smallest open-interval uniform draw produces this maximum countdown.
    poisson_allocation_sampler sampler(7046029254386353131ULL);
    allocation_sample before = sampler.sample(19260664ULL - 1, 0);
    XCTAssertEqual(before.object_weight, 0);
    XCTAssertEqual(before.byte_weight, 0);
    allocation_sample selected = sampler.sample(1, 0);
    XCTAssertGreaterThan(selected.object_weight, 0.0);
    XCTAssertTrue(std::isfinite(selected.object_weight));
    XCTAssertTrue(std::isfinite(selected.byte_weight));
    XCTAssertEqualWithAccuracy(selected.object_weight, 524288.5000001589, 0.000001);
    XCTAssertEqual(selected.byte_weight, selected.object_weight);
}

- (void)testDefaultConstructorSamplesAnUnsignedMaximumAllocation {
    poisson_allocation_sampler sampler;
    uint64_t size = std::numeric_limits<uint64_t>::max();
    allocation_sample sample = sampler.sample(size, 0);
    XCTAssertEqual(sample.object_weight, 1);
    XCTAssertEqual(sample.byte_weight, static_cast<double>(size));
    XCTAssertTrue(std::isfinite(sample.byte_weight));
}

- (void)testLargeAllocationRearmsOnceFromItsEnd {
    poisson_allocation_sampler actual(seed);
    poisson_allocation_sampler expected(seed);
    XCTAssertEqual(actual.sample(std::numeric_limits<uint64_t>::max(), 0).object_weight, 1);
    XCTAssertEqual(expected.sample(std::numeric_limits<uint64_t>::max() / 2, 0).object_weight, 1);

    // Overshoot must not change the next countdown or consume additional random draws.
    for (uint64_t index = 0; index < 10000; ++index) {
        allocation_sample sample = actual.sample(256, 0);
        allocation_sample comparison = expected.sample(256, 0);
        XCTAssertEqual(sample.object_weight, comparison.object_weight);
        XCTAssertEqual(sample.byte_weight, comparison.byte_weight);
    }
}

- (void)testSessionChangeDiscardsTheCountdownWithoutReseeding {
    poisson_allocation_sampler changedSession(seed);
    poisson_allocation_sampler continuousSession(seed);
    uint64_t size = std::numeric_limits<uint64_t>::max();
    changedSession.sample(size, 0);
    continuousSession.sample(size, 0);
    continuousSession.sample(size, 0);

    // Both now use the third draw: resetting discards the second draw, without reseeding.
    uint64_t selected = 0;
    for (uint64_t index = 0; index < 10000; ++index) {
        allocation_sample actual = changedSession.sample(256, 1);
        allocation_sample expected = continuousSession.sample(256, 0);
        XCTAssertEqual(actual.object_weight, expected.object_weight);
        XCTAssertEqual(actual.byte_weight, expected.byte_weight);
        selected += actual.object_weight != 0;
    }
    XCTAssertGreaterThan(selected, 0ULL);
}

- (void)testWeightsAreIndependentAndRemainFractionalUntilAccumulated {
    poisson_allocation_sampler sampler(seed);
    constexpr double probability = 0.6321205588285577; // 1 - exp(-1)
    constexpr double expectedObjectWeight = 1.5819767068693265;
    double objects = 0;
    double bytes = 0;
    uint64_t selected = 0;
    for (uint64_t index = 0; index < 100; ++index) {
        allocation_sample sample = sampler.sample(interval, 0);
        if (sample.object_weight == 0) {
            XCTAssertEqual(sample.byte_weight, 0);
            continue;
        }
        XCTAssertEqualWithAccuracy(sample.object_weight, expectedObjectWeight, 0.000000000001);
        XCTAssertEqualWithAccuracy(sample.byte_weight, static_cast<double>(interval) / probability, 0.000001);
        objects += sample.object_weight;
        bytes += sample.byte_weight;
        ++selected;
    }
    XCTAssertGreaterThan(selected, 0ULL);
    XCTAssertEqualWithAccuracy(objects, selected * expectedObjectWeight, 0.000000001);
    XCTAssertEqualWithAccuracy(bytes, selected * static_cast<double>(interval) / probability, 0.001);
    XCTAssertNotEqual(std::round(objects), selected * std::round(expectedObjectWeight));
}

- (void)testFixedSeedInclusionAndWeightedTotalsAcrossAllocationSizes {
    constexpr std::array<uint64_t, 4> sizes = {64, 4096, interval, 8 * interval};
    for (uint64_t size : sizes) {
        poisson_allocation_sampler sampler(seed);
        uint64_t count = size == 64 ? 2000000 : 100000;
        sampling_totals totals;
        for (uint64_t index = 0; index < count; ++index) {
            totals.add(sampler.sample(size, 0));
        }

        // Calculate the oracle independently of the sampler's numerically stable implementation.
        double probability = 1.0 - std::exp(-static_cast<double>(size) / interval);
        double selectionDeviation = std::sqrt(count * probability * (1.0 - probability));
        double objectDeviation = std::sqrt(count * (1.0 - probability) / probability);
        XCTAssertEqualWithAccuracy(static_cast<double>(totals.selected), count * probability,
                                   6.0 * selectionDeviation + 1.0, @"size = %llu", size);
        XCTAssertEqualWithAccuracy(totals.objects, static_cast<double>(count),
                                   6.0 * objectDeviation + 1.0, @"size = %llu", size);
        XCTAssertEqualWithAccuracy(totals.bytes, static_cast<double>(count) * size,
                                   (6.0 * objectDeviation + 1.0) * size, @"size = %llu", size);
    }
}

- (void)testConditionalSelectionProbabilityAfterAnUnsampledPrefix {
    constexpr std::array<uint64_t, 3> prefixes = {interval / 8, interval, 2 * interval};
    constexpr uint64_t probeSize = 4096;
    double probability = 1.0 - std::exp(-static_cast<double>(probeSize) / interval);
    for (uint64_t prefix : prefixes) {
        poisson_allocation_sampler sampler(seed);
        uint64_t survivors = 0;
        uint64_t selected = 0;
        for (uint64_t session = 0; session < 100000; ++session) {
            if (sampler.sample(prefix, session).object_weight == 0) {
                ++survivors;
                selected += sampler.sample(probeSize, session).object_weight != 0;
            }
        }

        // Condition on survival: the remaining countdown still has the same exponential law.
        XCTAssertGreaterThan(survivors, 0ULL);
        double deviation = std::sqrt(survivors * probability * (1.0 - probability));
        XCTAssertEqualWithAccuracy(static_cast<double>(selected), survivors * probability,
                                   6.0 * deviation + 1.0, @"prefix = %llu, survivors = %llu", prefix, survivors);
    }
}

- (void)testMixedAllocationSizesEstimateBothObjectAndByteTotals {
    poisson_allocation_sampler sampler(seed);
    constexpr std::array<uint64_t, 4> sizes = {64, 4096, interval, 8 * interval};
    constexpr uint64_t countPerSize = 100000;
    sampling_totals totals;
    double expectedObjects = 0;
    double expectedBytes = 0;
    double objectVariance = 0;
    double byteVariance = 0;
    for (uint64_t size : sizes) {
        double probability = 1.0 - std::exp(-static_cast<double>(size) / interval);
        double variance = countPerSize * (1.0 - probability) / probability;
        expectedObjects += countPerSize;
        expectedBytes += static_cast<double>(countPerSize) * size;
        objectVariance += variance;
        byteVariance += variance * size * size;
    }
    for (uint64_t index = 0; index < countPerSize; ++index) {
        for (uint64_t size : sizes) {
            totals.add(sampler.sample(size, 0));
        }
    }
    XCTAssertEqualWithAccuracy(totals.objects, expectedObjects, 6.0 * std::sqrt(objectVariance));
    XCTAssertEqualWithAccuracy(totals.bytes, expectedBytes, 6.0 * std::sqrt(byteVariance));
}

- (void)testConcurrentThreadsHaveIndependentSamplerState {
    poisson_allocation_sampler baselineSampler(seed);
    sampling_totals baseline = sample_workload(baselineSampler);
    std::array<sampling_totals, 8> results;
    std::array<std::thread, 8> threads;
    for (size_t index = 0; index < threads.size(); ++index) {
        threads[index] = std::thread([&results, index] {
            thread_local poisson_allocation_sampler sampler(seed);
            results[index] = sample_workload(sampler);
        });
    }
    for (std::thread &thread : threads) {
        thread.join();
    }
    for (sampling_totals result : results) {
        XCTAssertEqual(result.selected, baseline.selected);
        XCTAssertEqual(result.objects, baseline.objects);
        XCTAssertEqual(result.bytes, baseline.bytes);
    }
}

@end

#endif // !TARGET_OS_WATCH
