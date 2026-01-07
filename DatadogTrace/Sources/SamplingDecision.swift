/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Represents a span sampling decision, including the multiple mechanisms used to make a decision.
internal struct SamplingDecision {
    /// The decision mechanisms used in this decision.
    ///
    /// This dictionary should contain only the relevant mechanisms. For example, most `SamplingDecision`
    /// instances are created with an `.agentRate` mechanism, that should remain there for the lifetime
    /// of a decision. Conversely, the `.manual` mechanism should only be present when there is a manual
    /// override. In that situation, both mechanisms are kept, so the decision can revert to the `.agentRate`
    /// mechanism if the override is removed.
    ///
    /// - Remark: A `.fallback` mechanism always exists implicitly. However, as an optimization, it's not
    /// actually instantiated nor included in this dictionary. Getters like ``samplingPriority`` and
    /// ``decisionMaker`` should simulate its existence when necessary.
    private var mechanisms: [SamplingMechanismType: SamplingMechanism]

    /// Creates a sampling decision from the given sampling.
    ///
    /// - parameters:
    ///    - sampling: A `Sampling` used to obtain the initial sampling decision.
    init(sampling: Sampling) {
        let priority = sampling.sample() ? SamplingPriority.autoKeep : .autoDrop
        self.init(mechanisms: [.agentRate: FixedValueMechanism(samplingPriority: priority)])
    }

    private init(mechanisms: [SamplingMechanismType: SamplingMechanism]) {
        self.mechanisms = mechanisms
    }

    // TODO: RUM-12403 Remove this API
    init(temporaryPriority: SamplingPriority) {
        self.init(mechanisms: [.agentRate: FixedValueMechanism(samplingPriority: temporaryPriority)])
    }

    /// Marks this sampling decision as manually dropped.
    mutating func addManualDropOverride() {
        mechanisms[.manual] = FixedValueMechanism(samplingPriority: .manualDrop)
    }

    /// Marks this sampling decision as manually kept.
    mutating func addManualKeepOverride() {
        mechanisms[.manual] = FixedValueMechanism(samplingPriority: .manualKeep)
    }

    /// Removes any existing manual override, restoring the original sampling decision.
    mutating func removeManualOverride() {
        mechanisms[.manual] = nil
    }

    /// Obtains the sampling priority from this sampling decision.
    ///
    /// This is the sampling priority of the highest precedence mechanism registered in this decision.
    var samplingPriority: SamplingPriority {
        mechanisms
            .max { $0.0.precedence < $1.0.precedence }
            .map { $0.1.samplingPriority } ?? .autoKeep
    }

    /// Obtains the sampling mechanism used to obtain ``samplingPriority``.
    ///
    /// This is the highest precedence mechanism registered in this decision.
    var decisionMaker: SamplingMechanismType {
        mechanisms
            .max { $0.0.precedence < $1.0.precedence }
            .map { $0.0 } ?? .fallback
    }
}
