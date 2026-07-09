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
    /// Two namespaces are consumed: `rum` overrides the supported behavioral parameters, and `trace`
    /// configures distributed tracing on RUM's network instrumentation. Remote values take precedence,
    /// while any parameter the remote configuration omits keeps its in-code value; passing `nil` (no
    /// remote configuration was fetched) therefore leaves the configuration entirely unchanged.
    ///
    /// The two namespaces interact through RUM's URLSession instrumentation, which carries both
    /// resource collection and trace propagation: an explicit `rum.trackResources == false` disables
    /// that instrumentation, so it also suppresses `trace`, regardless of the hosts it declares.
    ///
    /// The merge happens once, at `RUM.enable(with:)` time; live updates after initialization are out
    /// of scope.
    ///
    /// - Parameter remoteConfiguration: The remote configuration to merge, or `nil` when none is
    ///   available (leaving this configuration unchanged).
    mutating func apply(remoteConfiguration: RemoteConfiguration?) {
        apply(rum: remoteConfiguration?.rum)

        if remoteConfiguration?.rum?.trackResources != false {
            apply(trace: remoteConfiguration?.trace)
        }
    }

    /// Applies the `rum` namespace, overriding the supported behavioral parameters with their remote
    /// values.
    ///
    /// Scalar and enum settings (sample rates, thresholds, tracking flags, vitals frequency) are
    /// overridden directly. `trackResources` and `trackUserInteractions` have no direct in-code
    /// equivalent — they are modeled as the presence of a tracking configuration / action predicate —
    /// so they are toggled through the `override(_:with:)` overloads instead. Thresholds arrive in
    /// milliseconds and are converted to seconds.
    ///
    /// - Parameter rum: The `rum` namespace, or `nil` to leave the configuration unchanged.
    private mutating func apply(rum: RemoteConfiguration.RUM?) {
        guard let rum else {
            return
        }

        override(\.telemetrySampleRate, with: rum.telemetrySampleRate.map { SampleRate($0) })
        override(\.trackAnonymousUser, with: rum.trackAnonymousUser)
        override(\.trackBackgroundEvents, with: rum.trackBackgroundEvents)
        override(\.trackFrustrations, with: rum.trackFrustrations)
        override(\.longTaskThreshold, with: rum.longTaskThresholdMs.map { .ddFromMilliseconds(.ddWithNoOverflow($0)) })
        override(\.appHangThreshold, with: rum.appHangThresholdMs.map { .ddFromMilliseconds(.ddWithNoOverflow($0)) })
        override(\.trackSlowFrames, with: rum.trackSlowFrames)
        override(\.trackWatchdogTerminations, with: rum.trackWatchdogTerminations)
        override(\.vitalsUpdateFrequency, with: rum.vitalsUpdateFrequency.map { VitalsFrequency($0) })
        override(\.urlSessionTracking, with: rum.trackResources)
        #if !os(watchOS)
        override(\.trackMemoryWarnings, with: rum.trackMemoryWarnings)
        override(\.uiKitActionsPredicate, with: rum.trackUserInteractions)
        override(\.swiftUIActionsPredicate, with: rum.trackUserInteractions)
        #endif
    }

    /// Applies the `trace` namespace, configuring distributed tracing for its first-party hosts.
    ///
    /// Trace propagation is carried by RUM's URLSession instrumentation, so configuring tracing also
    /// enables that instrumentation: when the developer provided no `urlSessionTracking`, a default one
    /// is created to hold the tracing configuration. An existing `urlSessionTracking` keeps its other
    /// settings (e.g. resource attributes, header capture), and its first-party hosts tracing is merged
    /// field by field — the remote hosts, sample rate, and injection strategy each replace the in-code
    /// value only when present.
    ///
    /// The host list drives whether propagation exists: a non-empty list configures (or replaces) it,
    /// while an explicit empty list clears it — stopping header injection on an in-code
    /// `urlSessionTracking` while leaving its other settings intact. When `tracedHosts` is omitted, a
    /// present sample rate / injection still updates existing propagation; an empty list is a no-op when
    /// no `urlSessionTracking` was configured in code (there is nothing to clear).
    ///
    /// - Parameter trace: The `trace` namespace, or `nil` to leave the configuration unchanged.
    private mutating func apply(trace: RemoteConfiguration.Trace?) {
        guard let trace else {
            return
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
            var tracking = urlSessionTracking ?? URLSessionTracking()
            tracking.firstPartyHostsTracing = URLSessionTracking.FirstPartyHostsTracing(
                trace,
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
            urlSessionTracking = tracking

        case .some:
            // An explicit empty list clears propagation, keeping any other instrumentation settings;
            // there is nothing to clear when no instrumentation was configured in code.
            if var tracking = urlSessionTracking {
                tracking.firstPartyHostsTracing = nil
                urlSessionTracking = tracking
            }

        case .none:
            // Hosts omitted: a present sample rate or injection strategy still updates existing
            // propagation; without existing propagation there are no hosts to configure.
            guard trace.sampleRate != nil || trace.traceContextInjection != nil,
                  var tracking = urlSessionTracking,
                  let firstPartyHostsTracing = tracking.firstPartyHostsTracing else {
                return
            }

            tracking.firstPartyHostsTracing = firstPartyHostsTracing
                .overriding(sampleRate: sampleRate, traceControlInjection: traceControlInjection)
            urlSessionTracking = tracking
        }
    }

    /// Overrides the value at `keyPath` with `remoteValue` when it is present.
    ///
    /// The merge primitive for a setting that maps one-to-one onto a stored property: a present remote
    /// value wins, an absent one (`nil`) leaves the in-code value untouched.
    ///
    /// - Parameters:
    ///   - keyPath: The configuration property to override.
    ///   - remoteValue: The remote value to apply, or `nil` when the remote configuration omits it.
    private mutating func override<Value>(_ keyPath: WritableKeyPath<Self, Value>, with remoteValue: Value?) {
        if let remoteValue {
            self[keyPath: keyPath] = remoteValue
        }
    }

    /// Toggles resource tracking, which is modeled in-code as the presence of `urlSessionTracking`.
    ///
    /// - `true` keeps any developer-provided configuration, installing a default one only when none is
    ///   set (so it never discards existing settings).
    /// - `false` clears it, disabling resource tracking.
    /// - `nil` leaves the current value untouched.
    ///
    /// - Parameters:
    ///   - keyPath: The `urlSessionTracking` property to toggle.
    ///   - enabled: The remote `trackResources` flag, or `nil` when omitted.
    private mutating func override(_ keyPath: WritableKeyPath<Self, URLSessionTracking?>, with enabled: Bool?) {
        if let enabled {
            self[keyPath: keyPath] = enabled
                ? self[keyPath: keyPath] ?? URLSessionTracking()
                : nil
        }
    }

    #if !os(watchOS)
    /// Toggles UIKit user-interaction tracking, which is modeled in-code as the presence of a UIKit
    /// action predicate.
    ///
    /// - `true` keeps any developer-provided predicate, installing the default one only when none is
    ///   set.
    /// - `false` clears it, disabling UIKit action tracking.
    /// - `nil` leaves the current value untouched.
    ///
    /// - Parameters:
    ///   - keyPath: The `uiKitActionsPredicate` property to toggle.
    ///   - enabled: The remote `trackUserInteractions` flag, or `nil` when omitted.
    private mutating func override(_ keyPath: WritableKeyPath<Self, UIKitRUMActionsPredicate?>, with enabled: Bool?) {
        if let enabled {
            self[keyPath: keyPath] = enabled
                ? self[keyPath: keyPath] ?? DefaultUIKitRUMActionsPredicate()
                : nil
        }
    }

    /// Toggles SwiftUI user-interaction tracking, which is modeled in-code as the presence of a SwiftUI
    /// action predicate.
    ///
    /// - `true` keeps any developer-provided predicate, installing the default one only when none is
    ///   set.
    /// - `false` clears it, disabling SwiftUI action tracking.
    /// - `nil` leaves the current value untouched.
    ///
    /// - Parameters:
    ///   - keyPath: The `swiftUIActionsPredicate` property to toggle.
    ///   - enabled: The remote `trackUserInteractions` flag, or `nil` when omitted.
    private mutating func override(_ keyPath: WritableKeyPath<Self, SwiftUIRUMActionsPredicate?>, with enabled: Bool?) {
        if let enabled {
            self[keyPath: keyPath] = enabled
                ? self[keyPath: keyPath] ?? DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
                : nil
        }
    }
    #endif
}

private extension RUM.Configuration.VitalsFrequency {
    /// Creates the in-code vitals frequency matching a remote `vitalsUpdateFrequency`.
    ///
    /// - Parameter remote: The remote vitals update frequency.
    /// - Returns: The matching `VitalsFrequency`, or `nil` for `.never` — which disables vitals
    ///   collection and has no in-code equivalent.
    init?(_ remote: RemoteConfiguration.RUM.VitalsUpdateFrequency) {
        switch remote {
        case .frequent: self = .frequent
        case .average: self = .average
        case .rare: self = .rare
        case .never: return nil
        }
    }
}

private extension RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing {
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
        }
    }
}
