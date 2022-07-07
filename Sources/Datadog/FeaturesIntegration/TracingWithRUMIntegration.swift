/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the current RUM context tags for produced `Spans`.
internal struct TracingWithRUMContextIntegration {
    private let rumContextIntegration = RUMContextIntegration()

    /// Produces `Span` tags describing the current RUM context.
    /// Returns `nil` and prints warning if global `RUMMonitor` is not registered.
    var currentRUMContextTags: [String: Encodable]? {
        guard let attributes = rumContextIntegration.currentRUMContextAttributes else {
            DD.logger.warn("RUM feature is enabled, but no `RUMMonitor` is registered. The RUM integration with Tracing will not work.")
            return nil
        }

        return attributes
    }
}
