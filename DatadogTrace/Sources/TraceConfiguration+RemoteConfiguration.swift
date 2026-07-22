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
    /// redacted status codes), and its first-party hosts tracing is merged field by field.
    ///
    /// The host list drives whether propagation exists: a non-empty list configures (or replaces) it,
    /// while an explicit empty list clears it — no host is treated as first-party, so no headers are
    /// injected, while an in-code `urlSessionTracking` keeps its other settings. When `tracedHosts` is
    /// omitted, existing propagation is preserved (only its sample rate / injection are updated if the
    /// remote provides them); an empty list is a no-op when no `urlSessionTracking` was configured in
    /// code (there is nothing to clear). Each entry in `tracedHosts` carries its own `propagatorTypes`,
    /// mapped directly onto the host's header formats — an empty list traces the host with no header
    /// formats.
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

        urlSessionTracking = urlSessionTracking?.overriding(with: trace) ?? URLSessionTracking(trace)
    }
}

private extension Trace.Configuration.URLSessionTracking {
    /// Returns a copy merging the remote `trace` namespace's first-party hosts tracing on top of this
    /// in-code configuration, leaving any other settings (e.g. redacted status codes) intact.
    ///
    /// The host list drives whether propagation exists: a non-empty list configures (or replaces) it,
    /// while an explicit empty list clears it. When `tracedHosts` is omitted, a present sample rate /
    /// injection still updates existing propagation. Either way, the sample rate and injection strategy
    /// fall back to the in-code value when the remote omits them.
    ///
    /// - Parameter trace: The remote `trace` namespace.
    /// - Returns: A copy with first-party hosts tracing merged with `trace`.
    func overriding(with trace: RemoteConfiguration.Trace) -> Self {
        var tracking = self
        let sampleRate = trace.sampleRate.map { SampleRate($0) }
        let traceControlInjection = trace.traceContextInjection.map { TraceContextInjection($0) }

        guard let tracedHosts = trace.tracedHosts else {
            // No hosts in the remote config: keep whatever propagation exists, refreshing only its
            // sample rate / injection strategy when the remote provides them.
            tracking.firstPartyHostsTracing = tracking.firstPartyHostsTracing.overriding(
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
            return tracking
        }

        if tracedHosts.isEmpty {
            // Explicit empty list: clear propagation, keeping any other instrumentation settings.
            tracking.firstPartyHostsTracing = .trace(hosts: [])
            return tracking
        }

        // Non-empty list: configure (or replace) propagation for these hosts.
        tracking.firstPartyHostsTracing = FirstPartyHostsTracing(
            tracedHosts,
            sampleRate: sampleRate ?? tracking.firstPartyHostsTracing.sampleRate,
            traceControlInjection: traceControlInjection ?? tracking.firstPartyHostsTracing.traceControlInjection
        )
        return tracking
    }

    /// Builds a fresh tracking configuration for a remote `trace` namespace, when no in-code
    /// `urlSessionTracking` exists to merge onto.
    ///
    /// - Parameter trace: The remote `trace` namespace.
    /// - Returns: A configuration holding the resulting first-party hosts tracing, or `nil` when `trace`
    ///   configures no propagation (nothing to instrument).
    init?(_ trace: RemoteConfiguration.Trace) {
        guard let tracedHosts = trace.tracedHosts, !tracedHosts.isEmpty else {
            return nil
        }

        self.init(firstPartyHostsTracing: FirstPartyHostsTracing(
            tracedHosts,
            sampleRate: trace.sampleRate.map { SampleRate($0) },
            traceControlInjection: trace.traceContextInjection.map { TraceContextInjection($0) }
        ))
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

    /// Builds first-party hosts tracing configuration for a non-empty list of remote traced hosts, with
    /// the given sample rate and injection strategy.
    ///
    /// Each host's `propagatorTypes` are mapped directly onto its header formats in `.traceWithHeaders`.
    ///
    /// - Parameters:
    ///   - tracedHosts: The remote `trace` namespace's traced hosts; must be non-empty.
    ///   - sampleRate: The trace propagation sample rate to apply.
    ///   - traceControlInjection: The trace context injection strategy to apply.
    init(_ tracedHosts: [RemoteConfiguration.Trace.TracedHosts], sampleRate: SampleRate?, traceControlInjection: TraceContextInjection?) {
        self = .traceWithHeaders(
            hostsWithHeaders: tracedHosts.reduce(into: [:]) {
                $0[$1.host] = Set($1.propagatorTypes.map { TracingHeaderType($0) })
            },
            sampleRate: sampleRate ?? .maxSampleRate,
            traceControlInjection: traceControlInjection ?? .sampled
        )
    }

    /// Returns a copy overriding the sample rate and/or injection strategy while preserving the hosts
    /// and any header formats. A `nil` argument keeps the current value.
    ///
    /// - Parameters:
    ///   - sampleRate: The trace propagation sample rate to apply, or `nil` to keep the current one.
    ///   - traceControlInjection: The trace context injection strategy to apply, or `nil` to keep the
    ///     current one.
    /// - Returns: A configuration with the same hosts (and header formats), the given sample rate and
    ///   injection strategy overriding the current ones where present.
    func overriding(sampleRate: SampleRate?, traceControlInjection: TraceContextInjection?) -> Self {
        switch self {
        case let .trace(hosts, currentSampleRate, currentInjection):
            return .trace(
                hosts: hosts,
                sampleRate: sampleRate ?? currentSampleRate,
                traceControlInjection: traceControlInjection ?? currentInjection
            )
        case let .traceWithHeaders(hostsWithHeaders, currentSampleRate, currentInjection):
            return .traceWithHeaders(
                hostsWithHeaders: hostsWithHeaders,
                sampleRate: sampleRate ?? currentSampleRate,
                traceControlInjection: traceControlInjection ?? currentInjection
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
    /// Maps a remote propagator type onto the in-code `TracingHeaderType`.
    ///
    /// - Parameter remote: The remote propagator type.
    init(_ remote: RemoteConfiguration.Trace.TracedHosts.PropagatorTypes) {
        switch remote {
        case .datadog: self = .datadog
        case .b3: self = .b3
        case .b3multi: self = .b3multi
        case .tracecontext: self = .tracecontext
        @unknown default: self = .datadog
        }
    }
}
