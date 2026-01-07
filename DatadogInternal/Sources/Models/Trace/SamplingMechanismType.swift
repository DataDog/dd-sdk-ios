/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

public enum SamplingMechanismType {
    case fallback
    case agentRate
    case manual

    public var tagValue: String {
        switch self {
        case .fallback:  "0"
        case .agentRate: "1"
        case .manual:    "4"
        }
    }
}
