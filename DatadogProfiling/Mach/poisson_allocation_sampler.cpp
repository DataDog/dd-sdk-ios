/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "poisson_allocation_sampler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <cmath>
#include <stdlib.h>

namespace dd::profiler {

namespace {

uint64_t system_random_seed() noexcept {
    uint64_t seed = 0;
    arc4random_buf(&seed, sizeof(seed));
    return seed;
}

} // namespace

poisson_allocation_sampler::poisson_allocation_sampler() noexcept
    : poisson_allocation_sampler(system_random_seed()) {}

poisson_allocation_sampler::poisson_allocation_sampler(uint64_t seed) noexcept
    : random_state_(seed) {}

allocation_sample poisson_allocation_sampler::weights_for_size(uint64_t size) noexcept {
    const double bytes = static_cast<double>(size);
    const double probability = -std::expm1(-bytes / static_cast<double>(sampling_interval_bytes));
    return {1.0 / probability, bytes / probability};
}

uint64_t poisson_allocation_sampler::next_random() noexcept {
    // SplitMix64 keeps only one word of state; unsigned arithmetic intentionally wraps.
    uint64_t value = (random_state_ += 0x9E3779B97F4A7C15ULL);
    value = (value ^ (value >> 30U)) * 0xBF58476D1CE4E5B9ULL;
    value = (value ^ (value >> 27U)) * 0x94D049BB133111EBULL;
    return value ^ (value >> 31U);
}

uint64_t poisson_allocation_sampler::next_interval() noexcept {
    // Use 52 random bits and their midpoint so the double is strictly inside (0, 1).
    // With this fixed mean the largest interval is about 19 MiB, safely below UINT64_MAX.
    const double uniform = (static_cast<double>(next_random() >> 12U) + 0.5) * 0x1.0p-52;
    const double interval = -std::log(uniform) * static_cast<double>(sampling_interval_bytes);
    return static_cast<uint64_t>(std::ceil(interval));
}

} // namespace dd::profiler

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
