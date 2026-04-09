/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ProfilingSamplerProvider: @unchecked Sendable {
    private let continuousSampleRate: SampleRate

    @ReadWriteLock
    private(set) var isContinuousProfilingEnabled: Bool

    let isContinuousProfilingConfigured: Bool

    init(continuousSampleRate: SampleRate) {
        self.continuousSampleRate = continuousSampleRate.normalized
        self.isContinuousProfilingEnabled = false
        self.isContinuousProfilingConfigured = continuousSampleRate > 0
    }

    func updateWith(deterministicSampler: DeterministicSampler) {
        isContinuousProfilingEnabled = deterministicSampler.combined(with: continuousSampleRate).sample()
    }
}
