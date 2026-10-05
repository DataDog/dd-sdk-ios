/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Trace.Configuration {
    /// Merges the remote configuration on top of this in-code configuration.
    ///
    /// The `trace` namespace overrides the span sample rate used by the default tracer. Distributed
    /// tracing enablement (first-party hosts tracing on URLSession instrumentation) is owned by RUM's
    /// remote configuration instead, to avoid registering overlapping URLSession handlers when both
    /// modules are enabled — see `RUMConfiguration+RemoteConfiguration.swift`.
    ///
    /// The merge happens once, at `Trace.enable(with:)` time; live updates after initialization are out
    /// of scope.
    ///
    /// - Parameter remoteConfiguration: The remote configuration to merge, or `nil` when none is
    ///   available (leaving this configuration unchanged).
    mutating func apply(remoteConfiguration: RemoteConfiguration?) {
        guard let trace = remoteConfiguration?.trace else {
            return
        }

        if let sampleRate = trace.sampleRate {
            self.sampleRate = SampleRate(sampleRate)
        }
    }
}
