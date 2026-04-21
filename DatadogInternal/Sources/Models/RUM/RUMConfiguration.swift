/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public let RUMFeatureName = "rum"

/// Provides a decision on sampling of requests to first party hosts.
public protocol RUMFirstPartyHostsTracingDecisionProvider {
    /// Obtains the decision on sampling of requests to first party hosts.
    ///
    /// This is based on the active session ID and tracing sampling rate, if enabled. The returned values are:
    /// * `true` if this both this session and first party host tracing are being sampled;
    /// * `false` if either this session or first party hosts tracing are not sampled, but first party hosts tracing is configured;
    /// * `nil` if there is no active session or if first party hosts tracing is not configured.
    var areFirstPartyHostsTraced: Bool? { get }
}

public extension DatadogFeature where Self: RUMFirstPartyHostsTracingDecisionProvider {
    static var name: String { RUMFeatureName }
}

