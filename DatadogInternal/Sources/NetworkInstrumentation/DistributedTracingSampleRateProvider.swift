/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides the sample rate of distributed tracing, if configured.
public protocol DistributedTracingSampleRateProvider {
    /// The distributed tracing (first party host tracing) sample rate, if configured. `nil` if first party hosting
    /// was not configured in RUM.
    var distributedTracingSampleRate: SampleRate? { get }
}

extension NetworkInstrumentationFeature: DistributedTracingSampleRateProvider {
    var distributedTracingSampleRate: SampleRate? {
        guard let urlSessionHandler = handlers
            .lazy
            .compactMap({ $0 as? DatadogURLSessionHandlerSupportingDistributedTracing })
            .first
        else {
            return nil
        }
        return urlSessionHandler.distributedTracingSampleRate
    }
}
