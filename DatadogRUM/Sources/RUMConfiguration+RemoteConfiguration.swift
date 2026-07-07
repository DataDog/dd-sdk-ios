/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUM.Configuration {
    /// Merges the remote configuration on top of this in-code configuration.
    ///
    /// The `rum` namespace overrides the supported behavioral parameters, and the `trace` namespace
    /// configures distributed tracing on RUM's network instrumentation. Remote values take precedence;
    /// parameters absent from the remote configuration keep their in-code value, and passing `nil`
    /// (no remote configuration available) leaves the configuration unchanged.
    ///
    /// The merge is applied once, at `RUM.enable(with:)` time. Live updates after initialization
    /// are out of scope.
    ///
    /// - Parameter remoteConfiguration: The remote configuration, or `nil`.
    mutating func apply(remoteConfiguration: RemoteConfiguration?) {
        apply(rum: remoteConfiguration?.rum)

        // Distributed tracing rides on RUM's network instrumentation, so an explicit
        // `rum.trackResources == false` (resource tracking disabled) also suppresses trace instrumentation.
        if remoteConfiguration?.rum?.trackResources != false {
            apply(trace: remoteConfiguration?.trace)
        }
    }

    /// Overrides the supported behavioral parameters from the `rum` namespace.
    private mutating func apply(rum: RemoteConfiguration.RUM?) {
        guard let rum else {
            return
        }

        if let telemetrySampleRate = rum.telemetrySampleRate {
            self.telemetrySampleRate = SampleRate(telemetrySampleRate)
        }
        if let trackAnonymousUser = rum.trackAnonymousUser {
            self.trackAnonymousUser = trackAnonymousUser
        }
        if let trackBackgroundEvents = rum.trackBackgroundEvents {
            self.trackBackgroundEvents = trackBackgroundEvents
        }
        if let trackFrustrations = rum.trackFrustrations {
            self.trackFrustrations = trackFrustrations
        }
        if let longTaskThresholdMs = rum.longTaskThresholdMs {
            self.longTaskThreshold = .ddFromMilliseconds(.ddWithNoOverflow(longTaskThresholdMs))
        }
        if let appHangThresholdMs = rum.appHangThresholdMs {
            self.appHangThreshold = .ddFromMilliseconds(.ddWithNoOverflow(appHangThresholdMs))
        }
        if let trackSlowFrames = rum.trackSlowFrames {
            self.trackSlowFrames = trackSlowFrames
        }
        if let trackWatchdogTerminations = rum.trackWatchdogTerminations {
            self.trackWatchdogTerminations = trackWatchdogTerminations
        }
        if let vitalsUpdateFrequency = rum.vitalsUpdateFrequency {
            self.vitalsUpdateFrequency = VitalsFrequency(vitalsUpdateFrequency)
        }
        // `trackResources` is modeled in-code as the presence of `urlSessionTracking`. Disabling
        // turns off resource tracking; enabling installs a default configuration only when the
        // developer did not provide one.
        if let trackResources = rum.trackResources {
            if !trackResources {
                self.urlSessionTracking = nil
            } else if self.urlSessionTracking == nil {
                self.urlSessionTracking = .init()
            }
        }

        #if !os(watchOS)
        if let trackMemoryWarnings = rum.trackMemoryWarnings {
            self.trackMemoryWarnings = trackMemoryWarnings
        }

        // `trackUserInteractions` is modeled in-code as the presence of action predicates. Disabling
        // removes any action predicate; enabling installs the default UIKit actions predicate only
        // when the developer did not provide any action predicate.
        if let trackUserInteractions = rum.trackUserInteractions {
            if !trackUserInteractions {
                self.uiKitActionsPredicate = nil
                self.swiftUIActionsPredicate = nil
            } else if self.uiKitActionsPredicate == nil, self.swiftUIActionsPredicate == nil {
                self.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
            }
        }
        #endif
    }

    /// Configures distributed tracing for the `trace` namespace's first-party hosts.
    ///
    /// As tracing is carried by RUM's network instrumentation, providing traced hosts also enables
    /// that instrumentation (creating a default `urlSessionTracking` when the developer set none).
    private mutating func apply(trace: RemoteConfiguration.Trace?) {
        guard let trace, let tracedHosts = trace.tracedHosts, !tracedHosts.isEmpty else {
            return
        }

        let hosts = Set(tracedHosts)
        let sampleRate = trace.sampleRate.map { SampleRate($0) } ?? .maxSampleRate
        let traceControlInjection = trace.traceContextInjection.map { TraceContextInjection($0) } ?? .sampled

        let firstPartyHostsTracing: URLSessionTracking.FirstPartyHostsTracing
        if let tracingHeaderTypes = trace.tracingHeaderTypes, !tracingHeaderTypes.isEmpty {
            let headerTypes = Set(tracingHeaderTypes.map { TracingHeaderType($0) })
            firstPartyHostsTracing = .traceWithHeaders(
                hostsWithHeaders: Dictionary(uniqueKeysWithValues: hosts.map { ($0, headerTypes) }),
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
        } else {
            firstPartyHostsTracing = .trace(
                hosts: hosts,
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
        }

        var tracking = urlSessionTracking ?? .init()
        tracking.firstPartyHostsTracing = firstPartyHostsTracing
        urlSessionTracking = tracking
    }
}

private extension RUM.Configuration.VitalsFrequency {
    /// Maps a remote vitals update frequency onto the in-code `VitalsFrequency`.
    /// `.never` disables vitals collection and therefore has no in-code equivalent (`nil`).
    init?(_ remote: RemoteConfiguration.RUM.VitalsUpdateFrequency) {
        switch remote {
        case .frequent: self = .frequent
        case .average: self = .average
        case .rare: self = .rare
        case .never: return nil
        }
    }
}

private extension TraceContextInjection {
    /// Maps a remote trace context injection strategy onto the in-code `TraceContextInjection`.
    init(_ remote: RemoteConfiguration.Trace.TraceContextInjection) {
        switch remote {
        case .all: self = .all
        case .sampled: self = .sampled
        }
    }
}

private extension TracingHeaderType {
    /// Maps a remote tracing header format onto the in-code `TracingHeaderType`.
    init(_ remote: RemoteConfiguration.Trace.TracingHeaderTypes) {
        switch remote {
        case .datadog: self = .datadog
        case .b3: self = .b3
        case .b3multi: self = .b3multi
        case .tracecontext: self = .tracecontext
        }
    }
}
