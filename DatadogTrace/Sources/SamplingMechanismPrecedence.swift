/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Precedence used to decide between multiple mechanisms in a ``SamplingDecision``.
/// Higher values mean higher precedence.
internal struct SamplingMechanismPrecedence: Comparable {
    static func < (lhs: SamplingMechanismPrecedence, rhs: SamplingMechanismPrecedence) -> Bool {
        lhs.precedence < rhs.precedence
    }

    let precedence: Int

    static let fallback =  SamplingMechanismPrecedence(precedence: 0)

    static let agentRate = SamplingMechanismPrecedence(precedence: 50)

    static let manual =    SamplingMechanismPrecedence(precedence: 80)
}

extension SamplingMechanismType {
    /// Precedence of this sampling mechanism.
    var precedence: SamplingMechanismPrecedence {
        switch self {
        case .fallback:  .fallback
        case .agentRate: .agentRate
        case .manual:    .manual
        }
    }
}

