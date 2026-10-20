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
///
/// The provider stores the resolved results rather than the deterministic sampler. Each result has
/// three states:
/// - `nil`: no RUM sampling decision received yet
/// - `true`: this profiling mode is eligible in the current RUM session
/// - `false`: this profiling mode is ineligible, either by configuration or sampling
internal final class ProfilingSamplerProvider: @unchecked Sendable {
    private let continuousSampleRate: SampleRate

    /// Session-linked sampling result for continuous profiling.
    ///
    /// The value is `nil` until a RUM context provides a `sessionSampler`. Once a context is received,
    /// the value becomes the result of composing the RUM session sampler with `continuousSampleRate`.
    @ReadWriteLock
    private(set) var continuousProfilingSampled: Bool?

    /// `true` when continuous profiling is configured with a sample rate greater than zero.
    let isContinuousProfilingConfigured: Bool

    /// Whether the native launch profile is available for the current configuration.
    let isAppLaunchProfilingAvailable: Bool

    /// Whether the current RUM session admits the available app-launch profile.
    @ReadWriteLock
    private(set) var appLaunchProfilingSampled: Bool?

    init(
        continuousSampleRate: SampleRate,
        appLaunchSampleRate: SampleRate = 0
    ) {
        self.continuousSampleRate = continuousSampleRate.normalizedSampleRate
        self.continuousProfilingSampled = nil
        self.appLaunchProfilingSampled = nil
        self.isContinuousProfilingConfigured = continuousSampleRate > 0
        self.isAppLaunchProfilingAvailable = appLaunchSampleRate > 0
    }

    /// Updates the session-linked sampling result from the current RUM session sampler.
    func updateWith(deterministicSampler: DeterministicSampler) {
        continuousProfilingSampled = deterministicSampler.combined(with: continuousSampleRate).sample()
        // Native startup already applied the app-launch rate; only RUM session eligibility remains.
        appLaunchProfilingSampled = isAppLaunchProfilingAvailable && deterministicSampler.isSampled
    }
}
