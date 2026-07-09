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
    /// The `trace` namespace overrides the span sample rate and configures distributed tracing on the
    /// module's URLSession instrumentation. Remote values take precedence, while any parameter the
    /// remote configuration omits keeps its in-code value; passing `nil` (no remote configuration was
    /// fetched) therefore leaves the configuration entirely unchanged.
    ///
    /// A single remote `sampleRate` drives both knobs consistently: the sampling rate of spans created
    /// with the default tracer (`sampleRate`) and the sampling rate of trace propagation on first-party
    /// hosts — the latter is updated even when the remote provides no hosts.
    ///
    /// Trace propagation is carried by the module's URLSession instrumentation, so configuring tracing
    /// also enables it: when the developer provided no `urlSessionTracking`, a default one is created to
    /// hold the tracing configuration. An existing `urlSessionTracking` keeps its other settings (e.g.
    /// redacted status codes), and its first-party hosts tracing is merged field by field — the remote
    /// hosts, sample rate, and injection strategy each replace the in-code value only when present.
    ///
    /// The host list drives whether propagation exists: a non-empty list configures (or replaces) it,
    /// while an explicit empty list clears it — no host is treated as first-party, so no headers are
    /// injected, while an in-code `urlSessionTracking` keeps its other settings. When `tracedHosts` is
    /// omitted, existing propagation is preserved (only its sample rate / injection are updated if the
    /// remote provides them); an empty list is a no-op when no `urlSessionTracking` was configured in
    /// code (there is nothing to clear).
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

        // Resolve the tracing sample rate and injection strategy: a present remote value wins,
        // otherwise the in-code value is kept, falling back to the module defaults when neither exists.
        let existing = urlSessionTracking?.firstPartyHostsTracing
        let sampleRate = trace.sampleRate.map { SampleRate($0) } ?? existing?.sampleRate ?? .maxSampleRate
        let traceControlInjection = trace.traceContextInjection
            .map { TraceContextInjection($0) } ?? existing?.traceControlInjection ?? .sampled

        switch trace.tracedHosts {
        case .some(let tracedHosts) where !tracedHosts.isEmpty:
            // A non-empty list configures (or replaces) propagation for the remote hosts.
            guard let firstPartyHostsTracing = URLSessionTracking.FirstPartyHostsTracing(
                trace,
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            ) else {
                return
            }

            if var tracking = urlSessionTracking {
                tracking.firstPartyHostsTracing = firstPartyHostsTracing
                urlSessionTracking = tracking
            } else {
                urlSessionTracking = URLSessionTracking(firstPartyHostsTracing: firstPartyHostsTracing)
            }

        case .some:
            // An explicit empty list clears propagation, keeping any other instrumentation settings;
            // there is nothing to clear when no instrumentation was configured in code.
            if var tracking = urlSessionTracking {
                tracking.firstPartyHostsTracing = .trace(hosts: [])
                urlSessionTracking = tracking
            }

        case .none:
            // Hosts omitted: a present sample rate or injection strategy still updates existing
            // propagation, so a single remote `sampleRate` drives both the span and propagation rates.
            guard trace.sampleRate != nil || trace.traceContextInjection != nil,
                  var tracking = urlSessionTracking else {
                return
            }

            tracking.firstPartyHostsTracing = tracking.firstPartyHostsTracing
                .overriding(sampleRate: sampleRate, traceControlInjection: traceControlInjection)
            urlSessionTracking = tracking
        }
    }
}

private extension Trace.Configuration.URLSessionTracking.FirstPartyHostsTracing {
    /// The trace propagation sample rate carried by this configuration.
    var sampleRate: SampleRate {
        switch self {
        case let .trace(_, sampleRate, _), let .traceWithHeaders(_, sampleRate, _):
            return sampleRate
        }
    }

    /// The trace context injection strategy carried by this configuration.
    var traceControlInjection: TraceContextInjection {
        switch self {
        case let .trace(_, _, injection), let .traceWithHeaders(_, _, injection):
            return injection
        }
    }

    /// Builds first-party hosts tracing configuration for a remote `trace` namespace's hosts.
    ///
    /// When header formats are provided they apply to every traced host (`.traceWithHeaders`);
    /// otherwise the default trace headers are used (`.trace`). The sample rate and injection strategy
    /// are resolved by the caller (remote value, else in-code value, else module default).
    ///
    /// - Parameters:
    ///   - trace: The remote `trace` namespace.
    ///   - sampleRate: The resolved trace propagation sample rate.
    ///   - traceControlInjection: The resolved trace context injection strategy.
    /// - Returns: The tracing configuration, or `nil` when no hosts are provided (nothing to instrument).
    init?(_ trace: RemoteConfiguration.Trace, sampleRate: SampleRate, traceControlInjection: TraceContextInjection) {
        guard let tracedHosts = trace.tracedHosts, !tracedHosts.isEmpty else {
            return nil
        }

        let hosts = Set(tracedHosts)

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

    /// Returns a copy overriding the sample rate and injection strategy while preserving the hosts and
    /// any header formats.
    ///
    /// - Parameters:
    ///   - sampleRate: The trace propagation sample rate to apply.
    ///   - traceControlInjection: The trace context injection strategy to apply.
    /// - Returns: A configuration with the same hosts (and header formats) but the given sample rate
    ///   and injection strategy.
    func overriding(sampleRate: SampleRate, traceControlInjection: TraceContextInjection) -> Self {
        switch self {
        case let .trace(hosts, _, _):
            return .trace(hosts: hosts, sampleRate: sampleRate, traceControlInjection: traceControlInjection)
        case let .traceWithHeaders(hostsWithHeaders, _, _):
            return .traceWithHeaders(
                hostsWithHeaders: hostsWithHeaders,
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
