//
//  SamplingDecision.swift
//  Datadog
//
//  Created by Miguel Arroz on 18/12/2025.
//  Copyright © 2025 Datadog. All rights reserved.
//

import Foundation
import DatadogInternal

///
///
internal struct SamplingDecision {
    private var mechanisms: [SamplingMechanismType: SamplingMechanism]

    internal init(sampling: Sampling) {
        let priority = sampling.sample() ? SamplingPriority.autoKeep : .autoDrop
        self.init(mechanisms: [.agentRate: FixedValueMechanism(samplingPriority: priority)])
    }

    private init(mechanisms: [SamplingMechanismType: SamplingMechanism]) {
        self.mechanisms = mechanisms
    }

    // TODO: Remove this API
    internal init(temporaryPriority: SamplingPriority) {
        self.init(mechanisms: [.agentRate: FixedValueMechanism(samplingPriority: temporaryPriority)])
    }

    mutating func addManualDropOverride() {
        mechanisms[.manual] = FixedValueMechanism(samplingPriority: .manualDrop)
    }

    mutating func addManualKeepOverride() {
        mechanisms[.manual] = FixedValueMechanism(samplingPriority: .manualKeep)
    }

    mutating func removeManualOverride() {
        mechanisms[.manual] = nil
    }

    internal var samplingPriority: SamplingPriority {
        mechanisms
            .max { $0.0.precedence < $1.0.precedence }
            .map { $0.1.samplingPriority } ?? .autoKeep
    }

    internal var decisionMaker: SamplingMechanismType {
        mechanisms
            .max { $0.0.precedence < $1.0.precedence }
            .map { $0.0 } ?? .fallback
    }
}
