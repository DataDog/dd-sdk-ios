/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Represents a span sampling decision, including the multiple mechanisms used to make a decision.
///
/// - Note: A few words on the rationale of why this is a class instead of a struct: although we keep the
/// sampling decision on a span context, the decision conceptually belongs to the trace. All the local spans
/// in a trace must have the same sampling decision. By using a class, we get this behavior for free: the
/// user may call `DDSpan.setTag(key: SpanTags.manualDrop, value: true)` on any of
/// the spans that are part of a trace to mark the entire trace as manually dropped, since all the span contexts
/// are pointing to the same instance of `SamplingDecision`.
internal final class SamplingDecision {
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
    @ReadWriteLock
    private var mechanisms: [SamplingMechanismType: any SamplingMechanism]

    /// Creates a sampling decision from the given sampling.
    ///
    /// - parameters:
    ///    - sampling: A `Sampling` used to obtain the initial sampling decision.
    convenience init(sampling: Sampling) {
        let priority = sampling.sample() ? SamplingPriority.autoKeep : .autoDrop
        self.init(mechanisms: [.agentRate: FixedValueMechanism(samplingPriority: priority)])
    }

    /// Creates a sampling decision based on a given sampling priority and decision maker.
    ///
    /// Use this method to create a sampling decision from possibly incomplete data, like values extracted from request headers.
    /// If `decisionMaker` is available, the sampling decision will use it. Otherwise, it uses the most appropriate mechanism
    /// for the given priority.
    ///
    /// - parameters:
    ///    - samplingPriority: The sampling priority for this decision.
    ///    - decisionMaker: The sampling decision maker if known, `nil` otherwise.
    convenience init(from samplingPriority: SamplingPriority, decisionMaker: SamplingMechanismType?) {
        if let decisionMaker {
            self.init(mechanisms: [decisionMaker: FixedValueMechanism(samplingPriority: samplingPriority)])
        } else if samplingPriority == .manualDrop || samplingPriority == .manualKeep {
            self.init(mechanisms: [.manual: FixedValueMechanism(samplingPriority: samplingPriority)])
        } else {
            self.init(mechanisms: [.agentRate: FixedValueMechanism(samplingPriority: samplingPriority)])
        }
    }

    private init(mechanisms: [SamplingMechanismType: any SamplingMechanism]) {
        self.mechanisms = mechanisms
    }

    /// Marks this sampling decision as manually dropped.
    func addManualDropOverride() {
        _mechanisms.mutate {
            $0[.manual] = FixedValueMechanism(samplingPriority: .manualDrop)
        }
    }

    /// Marks this sampling decision as manually kept.
    func addManualKeepOverride() {
        _mechanisms.mutate {
            $0[.manual] = FixedValueMechanism(samplingPriority: .manualKeep)
        }
    }

    /// Removes any existing manual override, restoring the original sampling decision.
    func removeManualOverride() {
        _mechanisms.mutate {
            $0[.manual] = nil
        }
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
