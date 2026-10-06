/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// How a feature's own sampling rate combines with the session sampling rate.
///
/// Both policies seed the sampler from the session ID, so the decision is stable for the whole
/// session. They differ only in which rate they apply, and that difference changes how much data a
/// feature keeps.
public enum SamplingRatePolicy: Sendable, Equatable {
    /// Apply the feature's rate on its own, taking only the seed from the session.
    ///
    /// The rate is absolute: a feature configured at 20% keeps 20% whether the session rate is 100%
    /// or 10%.
    case featureRate

    /// Multiply the feature's rate with the session rate, taking the seed from the session.
    ///
    /// The rate is a share of what the session already keeps: 20% inside a 10% session is an
    /// effective 2%.
    case combinedWithSessionRate
}

/// A session identity together with the sampling decision derived from it.
///
/// The ID and the decision are returned as one value on purpose. Reading them separately could pair
/// an ID from one session with a decision made for another if the session changed in between.
public struct SessionSamplingDecision: Sendable, Equatable {
    /// The session ID, in the format used on the wire.
    public let sessionID: String

    /// Whether the caller should keep data for this session, under the requested policy and rate.
    public let isSampled: Bool

    public init(sessionID: String, isSampled: Bool) {
        self.sessionID = sessionID
        self.isSampled = isSampled
    }
}

/// Synchronous access to the current session sampling state.
///
/// The session identity is also published through the core context, which reaches other features
/// after several asynchronous hops. Features that only create events can wait for those hops,
/// because events are written in order. Features that mutate an outgoing `URLRequest` cannot: by the
/// time the context lands, the request is already on the wire. Those features read this instead,
/// which resolves on the calling thread.
///
/// Obtain it with ``DatadogCoreProtocol/sessionSampler``. It is safe to store, and it resolves the
/// supplying feature on every call, so a feature can hold one from its own `enable()` even when the
/// session owner is enabled later.
public protocol SessionSampler {
    /// The current session identity, and the sampling decision for the given policy and rate.
    ///
    /// - Parameters:
    ///   - policy: How `rate` combines with the session rate. See ``SamplingRatePolicy``.
    ///   - rate: The caller's own sampling rate, between `0.0` and `100.0`. Passing
    ///     `SampleRate.maxSampleRate` with ``SamplingRatePolicy/combinedWithSessionRate`` yields the
    ///     session's own decision unchanged.
    /// - Returns: The decision, or `nil` when no session is available, in which case the caller
    ///   decides for itself.
    func decision(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingDecision?
}

/// Resolves the session sampler registered on a core, per call.
internal struct CoreSessionSampler: SessionSampler {
    /// A weak core reference.
    private weak var core: DatadogCoreProtocol?

    /// Creates a session sampler associated with a core instance.
    ///
    /// The `CoreSessionSampler` keeps a weak reference to the provided core.
    ///
    /// - Parameter core: The core instance.
    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    func decision(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingDecision? {
        core?
            .feature(named: Feature.rum, type: SessionSampler.self)?
            .decision(for: policy, rate: rate)
    }
}

public extension DatadogCoreProtocol {
    /// Synchronous access to the session sampling state on this core.
    ///
    /// Each core carries its own session, so a feature must read this from the core it was
    /// registered in. Returns decisions only while a session exists on that core.
    var sessionSampler: SessionSampler { CoreSessionSampler(core: self) }
}
