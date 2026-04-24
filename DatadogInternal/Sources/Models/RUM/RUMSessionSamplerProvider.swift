/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public let RUMFeatureName = "rum"

/// Provides the RUM session deterministic sampler for the active session.
public protocol RUMSessionSamplerProvider {
    /// The RUM session deterministic sampler for the active session. `nil` if there is no active session.
    var rumSessionSampler: DeterministicSampler? { get }
}

public extension DatadogFeature where Self: RUMSessionSamplerProvider {
    static var name: String { RUMFeatureName }
}

