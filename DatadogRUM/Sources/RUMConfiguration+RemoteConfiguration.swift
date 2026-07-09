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
    /// settings (e.g. resource attributes, header capture) — only its first-party hosts tracing is
    /// replaced.
    ///
    /// The host list drives the outcome: a non-empty list configures (or replaces) trace propagation,
    /// while an explicit empty list clears it — stopping header injection on an in-code
    /// `urlSessionTracking` while leaving its other settings intact. When `tracedHosts` is omitted
    /// (or the whole `trace` namespace is `nil`), nothing is described and the configuration is left
    /// unchanged; likewise, an empty list is a no-op when no `urlSessionTracking` was configured in
    /// code (there is nothing to clear).
    ///
    /// - Parameter trace: The `trace` namespace, or `nil` to leave the configuration unchanged.
    private mutating func apply(trace: RemoteConfiguration.Trace?) {
        guard let trace, let tracedHosts = trace.tracedHosts else {
            return
        }

        // A non-empty list configures propagation; an explicit empty list clears it.
        let firstPartyHostsTracing = tracedHosts.isEmpty
            ? nil
            : URLSessionTracking.FirstPartyHostsTracing(trace)

        // An empty list has nothing to clear when no instrumentation was configured in code.
        guard urlSessionTracking != nil || firstPartyHostsTracing != nil else {
            return
        }

        var tracking = urlSessionTracking ?? URLSessionTracking()
        tracking.firstPartyHostsTracing = firstPartyHostsTracing
        urlSessionTracking = tracking
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
