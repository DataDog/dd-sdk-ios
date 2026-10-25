/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Stores profiling sampling decisions.
///
/// It keeps the RUM session-linked decisions for each profiling mode:
/// - `isContinuousProfilingConfigured` reflects the configured `continuousSampleRate`
/// - `continuousProfilingSampled` reflects the current RUM-linked sampling result
/// - `appLaunchProfilingSampled` reflects whether the current RUM session admits the launch profile
/// - `memory.sampled` reflects the independent memory profiling result for that session
///
/// The provider stores the resolved results rather than the deterministic sampler. Each result has
/// three states:
/// - `nil`: no RUM sampling decision received yet
/// - `true`: this profiling mode is eligible in the current RUM session
/// - `false`: this profiling mode is ineligible, either by configuration or sampling
///
/// Memory decisions can also be resolved for a supplied session without changing the stored results.
internal final class ProfilingSamplerProvider: @unchecked Sendable {
    @ReadWriteLock
    private var cpu: Sampling

    @ReadWriteLock
    private(set) var memory: Sampling

    /// Session-linked sampling result for continuous profiling.
    ///
    /// The value is `nil` until a RUM context provides a `sessionSampler`. Once a context is received,
    /// the value becomes the result of composing the RUM session sampler with `continuousSampleRate`.
    var continuousProfilingSampled: Bool? { cpu.sampled }

    /// `true` when continuous profiling is configured with a sample rate greater than zero.
    var isContinuousProfilingConfigured: Bool { cpu.isConfigured }

    /// Whether the native launch profile is available for the current configuration.
    var isAppLaunchProfilingAvailable: Bool { cpu.isAppLaunchConfigured }

    /// Whether the current RUM session admits the available app-launch profile.
    var appLaunchProfilingSampled: Bool? { cpu.appLaunchSampled }

    init(
        continuousSampleRate: SampleRate,
        appLaunchSampleRate: SampleRate = 0,
        memorySampleRate: SampleRate = 0
    ) {
        cpu = Sampling(
            sampleRate: continuousSampleRate.normalizedSampleRate,
            isConfigured: continuousSampleRate > 0,
            isAppLaunchConfigured: appLaunchSampleRate > 0
        )
        let normalizedMemorySampleRate = memorySampleRate.normalizedSampleRate
        memory = Sampling(
            sampleRate: normalizedMemorySampleRate,
            isConfigured: normalizedMemorySampleRate > 0,
            isAppLaunchConfigured: normalizedMemorySampleRate > 0
        )
    }

    /// Updates the session-linked sampling result from the current RUM session sampler.
    func updateWith(deterministicSampler: DeterministicSampler) {
        _cpu.mutate { $0.update(with: deterministicSampler) }
        _memory.mutate { $0.update(with: deterministicSampler) }
    }

    struct Sampling {
        let sampleRate: SampleRate
        let isConfigured: Bool
        let isAppLaunchConfigured: Bool
        var sampled: Bool?
        var appLaunchSampled: Bool?

        func sampled(for sessionSampler: DeterministicSampler?) -> Bool? {
            sessionSampler.map { $0.combined(with: sampleRate).sample() }
        }

        func appLaunchSampled(for sessionSampler: DeterministicSampler?) -> Bool? {
            // Native startup already applied the app-launch rate; only RUM session eligibility remains.
            sessionSampler.map { isAppLaunchConfigured && $0.isSampled }
        }

        mutating func update(with sessionSampler: DeterministicSampler) {
            sampled = sampled(for: sessionSampler)
            appLaunchSampled = appLaunchSampled(for: sessionSampler)
        }
    }
}
