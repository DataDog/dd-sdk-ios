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
    /// while most parameters the remote configuration omits keep their in-code value — the exceptions are
    /// the `longTaskThreshold` and `appHangThreshold`, whose absence disables the corresponding feature
    /// (see `apply(rum:)`). Passing `nil` (no remote configuration was fetched) leaves the configuration
    /// entirely unchanged.
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
    /// Scalar and enum settings (sample rates, tracking flags, vitals frequency) are overridden
    /// directly. `trackResources` and `trackUserInteractions` have no direct in-code equivalent — they
    /// are modeled as the presence of a tracking configuration / action predicate — so they are toggled
    /// through the `override(_:with:)` overloads instead.
    ///
    /// `longTaskThreshold` and `appHangThreshold` are overridden through `override(_:with:)` for
    /// `AppHang`/`LongTask`, which follows: an explicit `enabled == false` clears the in-code value
    /// (disabling the feature); otherwise a present `threshold` overrides it (converted from
    /// milliseconds to seconds); an omitted `threshold` (or an omitted `appHang`/`longTask` namespace)
    /// leaves the in-code value untouched.
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
        override(\.longTaskThreshold, with: rum.longTask)
        override(\.appHangThreshold, with: rum.appHang)
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
    /// Each entry in `tracedHosts` carries its own `propagatorTypes`, mapped directly onto the host's
    /// header formats — an empty list traces the host with no header formats.
    ///
    /// - Parameter trace: The `trace` namespace, or `nil` to leave the configuration unchanged.
    private mutating func apply(trace: RemoteConfiguration.Trace?) {
        guard let trace else {
            return
        }

        urlSessionTracking = urlSessionTracking?.overriding(with: trace) ?? URLSessionTracking(trace)
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

    /// Overrides a threshold property (stored in seconds) with a remote `appHang`/`longTask` value.
    ///
    /// An explicit `enabled == false` clears the property, disabling the feature regardless of
    /// `threshold`. Otherwise, a present `threshold` (in milliseconds) overrides the property, converted
    /// to seconds. An omitted `threshold` — or an omitted `remote` namespace entirely — leaves the
    /// in-code value untouched.
    ///
    /// - Parameters:
    ///   - keyPath: The threshold property to override.
    ///   - remote: The remote `appHang` or `longTask` configuration, or `nil` when omitted.
    private mutating func override(_ keyPath: WritableKeyPath<Self, TimeInterval?>, with remote: RemoteThreshold?) {
        if remote?.enabled == false {
            self[keyPath: keyPath] = nil
        } else if let threshold = remote?.threshold {
            self[keyPath: keyPath] = .ddFromMilliseconds(.ddWithNoOverflow(threshold))
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

/// A remote `appHang`/`longTask` configuration: an `enabled` switch and a `threshold` in milliseconds.
private protocol RemoteThreshold {
    var enabled: Bool? { get }
    var threshold: Double? { get }
}

extension RemoteConfiguration.RUM.AppHang: RemoteThreshold {}
extension RemoteConfiguration.RUM.LongTask: RemoteThreshold {}

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

private extension RUM.Configuration.URLSessionTracking {
    /// Returns a copy merging the remote `trace` namespace's first-party hosts tracing on top of this
    /// in-code configuration, leaving any other settings (e.g. resource attributes, header capture)
    /// intact.
    ///
    /// The host list drives whether propagation exists: a non-empty list configures (or replaces) it,
    /// while an explicit empty list clears it. When `tracedHosts` is omitted, a present sample rate /
    /// injection still updates existing propagation; there is nothing to clear or update when no
    /// propagation was configured in code. Either way, the sample rate and injection strategy fall back
    /// to the in-code value, then the module default, when the remote omits them.
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
            tracking.firstPartyHostsTracing = tracking.firstPartyHostsTracing?.overriding(
                sampleRate: sampleRate,
                traceControlInjection: traceControlInjection
            )
            return tracking
        }

        if tracedHosts.isEmpty {
            // Explicit empty list: clear propagation.
            tracking.firstPartyHostsTracing = nil
            return tracking
        }

        // Non-empty list: configure (or replace) propagation for these hosts.
        tracking.firstPartyHostsTracing = FirstPartyHostsTracing(
            tracedHosts,
            sampleRate: sampleRate ?? tracking.firstPartyHostsTracing?.sampleRate,
            traceControlInjection: traceControlInjection ?? tracking.firstPartyHostsTracing?.traceControlInjection
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
        let tracking = Self().overriding(with: trace)
        guard tracking.firstPartyHostsTracing != nil else {
            return nil
        }
        self = tracking
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
        }
    }
}
