//
//  SamplingMechanisms.swift
//  Datadog
//
//  Created by Miguel Arroz on 18/12/2025.
//  Copyright © 2025 Datadog. All rights reserved.
//

import Foundation
import DatadogInternal

extension SamplingMechanismType {
    var precedence: SamplingMechanismPrecedence {
        switch self {
        case .fallback:  .fallback
        case .agentRate: .agentRate
        case .manual:    .manual
        }
    }
}

internal struct SamplingMechanismPrecedence: Comparable {
    static func < (lhs: SamplingMechanismPrecedence, rhs: SamplingMechanismPrecedence) -> Bool {
        lhs.precedence < rhs.precedence
    }

    let precedence: Int

    static let fallback =  SamplingMechanismPrecedence(precedence: 0)

    static let agentRate = SamplingMechanismPrecedence(precedence: 50)

    static let manual =    SamplingMechanismPrecedence(precedence: 80)
}

internal protocol SamplingMechanism {
    var samplingPriority: SamplingPriority { get }
}

internal struct FixedValueMechanism: SamplingMechanism {
    let samplingPriority: SamplingPriority
}
