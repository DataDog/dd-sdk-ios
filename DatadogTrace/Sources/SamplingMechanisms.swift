//
//  SamplingMechanisms.swift
//  Datadog
//
//  Created by Miguel Arroz on 18/12/2025.
//  Copyright © 2025 Datadog. All rights reserved.
//

import Foundation
import DatadogInternal

internal enum SamplingMechanismType {
    case manual
    case customSamplingRules

    var precedence: SamplingMechanismPrecedence {
        switch self {
        case .manual: .manual
        case .customSamplingRules: .customSamplingRules
        }
    }
}

internal struct SamplingMechanismPrecedence: Comparable {
    static func < (lhs: SamplingMechanismPrecedence, rhs: SamplingMechanismPrecedence) -> Bool {
        lhs.precedence < rhs.precedence
    }

    let precedence: Int

    static let manual =              SamplingMechanismPrecedence(precedence: 1000)

    static let customSamplingRules = SamplingMechanismPrecedence(precedence: 1)
}

internal protocol SamplingMechanism {
    var samplingPriority: SamplingPriority { get }
}

internal struct FixedValueMechanism: SamplingMechanism {
    let samplingPriority: SamplingPriority
}
