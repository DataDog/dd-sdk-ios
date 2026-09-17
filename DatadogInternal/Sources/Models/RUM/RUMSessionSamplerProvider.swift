/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// How a feature's own sampling rate relates to the RUM session sampling rate.
///
/// Both policies seed the sampler from the RUM session ID, so the decision is stable for the whole
/// session. They differ in which rate they apply, and the difference is not cosmetic: picking the
/// wrong one silently multiplies or fails to multiply the configured rate.
public enum SamplingRatePolicy: Sendable, Equatable {
    /// Apply the feature's rate on its own, using the session only as the seed.
    ///
    /// The configured rate is absolute. A feature set to 20% keeps 20% of sessions whether the RUM
    /// session rate is 100% or 10%. Manual Trace spans use this, because
    /// `Trace.Configuration.sampleRate` is documented as the trace sampling rate rather than a
    /// share of RUM.
    case featureRate

    /// Multiply the feature's rate with the RUM session rate, using the session as the seed.
    ///
    /// The configured rate is a share of the sessions RUM already kept. A feature set to 20% inside
    /// a 10% RUM session has an effective rate of 2%. The URLSession handlers and WebView tracking
    /// use this, because their rate applies on top of a tracked session.
    case combinedWithSessionRate
}

/// The RUM session identity together with the sampling decision derived from it.
///
/// The ID and the decision are returned as one value on purpose. A consumer that read them in two
/// steps could pair an ID from one session with a decision made for another if the session rolled
/// over in between, which produces events that look tracked but cannot be correlated.
public struct SessionSamplingSnapshot: Sendable, Equatable {
    /// The RUM session ID, in the format used on the wire.
    public let sessionID: String

    /// Whether the consumer should keep data for this session, under the requested policy and rate.
    public let isSampled: Bool

    public init(sessionID: String, isSampled: Bool) {
        self.sessionID = sessionID
        self.isSampled = isSampled
    }
}

/// Synchronous access to the RUM session sampling state, without going through the message bus.
///
/// RUM publishes its session through the core context, which reaches other features after three
/// asynchronous hops. Features that only create events can wait for those hops, because events are
/// written in order. Features that mutate an outgoing `URLRequest` cannot: by the time the context
/// lands, the request is already on the wire, and the tracing headers it should have carried are
/// missing for good. Those features read this instead, which resolves on the calling thread.
///
/// Obtain it through ``DatadogCoreProtocol/rumSessionSampling``. Resolve it per read rather than
/// caching the result, since RUM can be enabled after the reading feature.
public protocol RUMSessionSamplerProvider: AnyObject {
    /// The current session identity, and the sampling decision for the given policy and rate.
    ///
    /// The returned snapshot is derived from a single read of the session state, so the ID and the
    /// decision always belong to the same session.
    ///
    /// - Parameters:
    ///   - policy: How `rate` relates to the RUM session sampling rate. See ``SamplingRatePolicy``.
    ///   - rate: The consumer's own sampling rate, between `0.0` and `100.0`. Passing
    ///     `SampleRate.maxSampleRate` with ``SamplingRatePolicy/combinedWithSessionRate`` yields the
    ///     session's own decision unchanged.
    /// - Returns: The snapshot, or `nil` when no session is active, for example before RUM creates
    ///   its first session or after `stopSession()`. Consumers fall back to their own sampling then.
    func sessionSamplingSnapshot(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingSnapshot?
}

public extension DatadogCoreProtocol {
    /// Synchronous access to the RUM session sampling state on this core, or `nil` when RUM is not
    /// enabled on it.
    ///
    /// Each core carries its own RUM session, so a feature must read this from the same core it was
    /// registered in. Resolve it per read: RUM can be enabled after the reading feature.
    var rumSessionSampling: RUMSessionSamplerProvider? {
        feature(named: Feature.rum, type: RUMSessionSamplerProvider.self)
    }
}
