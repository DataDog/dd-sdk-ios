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
    /// The `trace` namespace overrides the span sample rate and, when it provides hosts, configures
    /// distributed tracing on the module's URLSession instrumentation. Remote values take precedence,
    /// while any parameter the remote configuration omits keeps its in-code value; passing `nil` (no
    /// remote configuration was fetched) therefore leaves the configuration entirely unchanged.
    ///
    /// A single remote `sampleRate` drives both knobs consistently: the sampling rate of spans created
    /// with the default tracer (`sampleRate`) and the sampling rate of trace propagation on first-party
    /// hosts.
    ///
    /// Trace propagation is carried by the module's URLSession instrumentation, so configuring tracing
    /// also enables it: when the developer provided no `urlSessionTracking`, a default one is created to
    /// hold the tracing configuration. An existing `urlSessionTracking` keeps its other settings (e.g.
    /// redacted status codes) — only its first-party hosts tracing is replaced.
    ///
    /// The host list drives the outcome: a non-empty list configures (or replaces) trace propagation,
    /// while an explicit empty list clears it — no host is treated as first-party, so no headers are
    /// injected, while an in-code `urlSessionTracking` keeps its other settings. When `tracedHosts` is
    /// omitted, nothing is described and only the span sample rate above is affected; likewise, an empty
    /// list is a no-op when no `urlSessionTracking` was configured in code (there is nothing to clear).
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

        guard let tracedHosts = trace.tracedHosts else {
            return // Hosts omitted: nothing to instrument, only the span sample rate is affected.
        }

        if tracedHosts.isEmpty {
            // An explicit empty list clears trace propagation, keeping any other instrumentation
            // settings; there is nothing to clear when no instrumentation was configured in code.
            if var tracking = urlSessionTracking {
                tracking.firstPartyHostsTracing = .trace(hosts: [])
                urlSessionTracking = tracking
            }
            return
        }

        guard let firstPartyHostsTracing = URLSessionTracking.FirstPartyHostsTracing(trace) else {
            return
        }

        if var tracking = urlSessionTracking {
            tracking.firstPartyHostsTracing = firstPartyHostsTracing
            urlSessionTracking = tracking
        } else {
            urlSessionTracking = URLSessionTracking(firstPartyHostsTracing: firstPartyHostsTracing)
        }
    }
}

private extension Trace.Configuration.URLSessionTracking.FirstPartyHostsTracing {
    /// Builds first-party hosts tracing configuration from a remote `trace` namespace.
    ///
    /// When header formats are provided they apply to every traced host (`.traceWithHeaders`);
    /// otherwise the default trace headers are used (`.trace`). A missing sample rate defaults to
    /// `.maxSampleRate` and a missing injection strategy to `.sampled`.
    ///
    /// - Parameter trace: The remote `trace` namespace.
    /// - Returns: The tracing configuration, or `nil` when no hosts are provided (nothing to instrument).
    init?(_ trace: RemoteConfiguration.Trace) {
        guard let tracedHosts = trace.tracedHosts, !tracedHosts.isEmpty else {
            return nil
        }

        let hosts = Set(tracedHosts)
        let sampleRate = trace.sampleRate.map { SampleRate($0) } ?? .maxSampleRate
        let traceControlInjection = trace.traceContextInjection.map { TraceContextInjection($0) } ?? .sampled

        if let tracingHeaderTypes = trace.tracingHeaderTypes, !tracingHeaderTypes.isEmpty {
            let headerTypes = Set(tracingHeaderTypes.map { TracingHeaderType($0) })
            self = .traceWithHeaders(
                hostsWithHeaders: Dictionary(uniqueKeysWithValues: hosts.map { ($0, headerTypes) }),
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
        } else {
            self = .trace(
                hosts: hosts,
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
        }
    }
}

private extension TraceContextInjection {
    /// Maps a remote trace context injection strategy onto the in-code `TraceContextInjection`.
    ///
    /// - Parameter remote: The remote injection strategy.
    init(_ remote: RemoteConfiguration.Trace.TraceContextInjection) {
        switch remote {
        case .all: self = .all
        case .sampled: self = .sampled
        @unknown default: self = .sampled
        }
    }
}

private extension TracingHeaderType {
    /// Maps a remote tracing header format onto the in-code `TracingHeaderType`.
    ///
    /// - Parameter remote: The remote tracing header format.
    init(_ remote: RemoteConfiguration.Trace.TracingHeaderTypes) {
        switch remote {
        case .datadog: self = .datadog
        case .b3: self = .b3
        case .b3multi: self = .b3multi
        case .tracecontext: self = .tracecontext
        @unknown default: self = .datadog
        }
    }
}
