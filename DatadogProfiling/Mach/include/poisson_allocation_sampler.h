/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_POISSON_ALLOCATION_SAMPLER_H_
#define DD_PROFILER_POISSON_ALLOCATION_SAMPLER_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <cstdint>

namespace dd::profiler {

/// Independent estimates of the object count and byte count represented by a selected allocation.
/// Accumulate these weights as doubles before rounding; rounding each sample biases the estimates.
struct allocation_sample {
    double object_weight;
    double byte_weight;
};

/**
 * Samples allocations with Poisson points spaced by an average of 512 KiB.
 *
 * This class is thread-confined. Allocation observers must own a separate instance for each
 * calling thread, for example with thread_local storage. sample() performs no synchronization
 * or dynamic allocation; construction with the system random source has a separate cost.
 */
class poisson_allocation_sampler {
public:
    static constexpr uint64_t sampling_interval_bytes = 512ULL * 1024ULL;

    /// Returns the mean byte interval between Poisson points.
    static constexpr uint64_t sampling_interval() noexcept { return sampling_interval_bytes; }

    /// Seeds the compact random source once from the system RNG. Construction calls arc4random_buf
    /// and is outside sample()'s synchronization and allocation guarantees.
    poisson_allocation_sampler() noexcept;

    /// Creates a sampler from caller-provided entropy or a reproducible random seed.
    explicit poisson_allocation_sampler(uint64_t seed) noexcept;

    ~poisson_allocation_sampler() = default;

    poisson_allocation_sampler(const poisson_allocation_sampler&) = delete;
    poisson_allocation_sampler& operator=(const poisson_allocation_sampler&) = delete;
    poisson_allocation_sampler(poisson_allocation_sampler&&) noexcept = default;
    poisson_allocation_sampler& operator=(poisson_allocation_sampler&&) = delete;

    /**
     * Returns both weights for a selected allocation, or two zero weights otherwise.
     *
     * The caller supplies the session token. Each new profiling session observed by this instance
     * must have a distinct token, including sessions after the observer stops and restarts.
     * A changed token discards the previous countdown and draws a fresh interval on the first
     * nonzero allocation. Zero-byte allocations do not change sampler state.
     *
     * An allocation crossing one or more Poisson points produces only one sample. The next
     * interval starts at the allocation's end, using the exponential distribution's memorylessness.
     */
    allocation_sample sample(uint64_t size, uint64_t session_id) noexcept {
        if (size == 0) {
            return {};
        }

        if (!has_session_ || session_id != session_id_) {
            session_id_ = session_id;
            has_session_ = true;
            bytes_until_sample_ = next_interval();
        }

        // Compare before subtracting so even a UINT64_MAX allocation cannot wrap the countdown.
        if (size < bytes_until_sample_) {
            bytes_until_sample_ -= size;
            return {};
        }

        // The next Poisson point after the object's end has a fresh exponential wait.
        bytes_until_sample_ = next_interval();
        return weights_for_size(size);
    }

private:
    static allocation_sample weights_for_size(uint64_t size) noexcept;
    uint64_t next_random() noexcept;
    uint64_t next_interval() noexcept;

    uint64_t random_state_;
    uint64_t bytes_until_sample_ = 0;
    uint64_t session_id_ = 0;
    bool has_session_ = false;
};

} // namespace dd::profiler

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_PROFILER_POISSON_ALLOCATION_SAMPLER_H_
