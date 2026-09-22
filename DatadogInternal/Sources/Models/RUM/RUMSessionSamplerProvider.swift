/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides the deterministic sampler for the current RUM session.
public protocol RUMSessionSamplerProvider {
    /// The deterministic sampler for the current RUM session, including the initial session while it is
    /// still being created.
    ///
    /// The initial session's identity is created synchronously inside `RUM.enable()`, so this is populated
    /// by the time `RUM.enable()` returns, before the session scope itself exists. It is `nil` when RUM is
    /// not enabled, and while no session is active, for example after `stopSession()`.
    var rumSessionSampler: DeterministicSampler? { get }
}

public extension DatadogFeature where Self: RUMSessionSamplerProvider { }
