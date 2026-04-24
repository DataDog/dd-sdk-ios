//
//  DistributedTracingSampleRateProvider.swift
//  DatadogInternal
//
//  Created by Miguel Arroz on 24/04/2026.
//  Copyright © 2026 Datadog. All rights reserved.
//

import Foundation

/// Provides the sample rate of distributed tracing, if configured.
public protocol DistributedTracingSampleRateProvider {
    /// The distributed tracing (first party host tracing) sample rate, if configured. `nil` if first party hosting
    /// was not configured in RUM.
    var distributedTracingSampleRate: SampleRate? { get }
}

extension NetworkInstrumentationFeature: DistributedTracingSampleRateProvider {
    var distributedTracingSampleRate: SampleRate? {
        guard let urlSessionHandler = handlers.first as? DatadogURLSessionHandlerSupportingDistributedTracing else {
            return nil
        }
        return urlSessionHandler.distributedTracingSampleRate
    }
}
