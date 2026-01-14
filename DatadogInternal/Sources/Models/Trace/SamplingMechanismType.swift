/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// The mechanism used to make a span sampling decision.
public enum SamplingMechanismType: Equatable {
    /// Fallback mechanism. This mechanism samples all spans. It should never be used, but it's included for completion.
    case fallback
    /// The main decision mechanism. Although the SDK runs in an agent-less scenario, we consider the SDK sampling
    /// decisions act as the agent rate in scenarios with independent tracers and agent.
    case agentRate
    /// Decision mechanism used when a decision is manually set by the developer.
    case manual

    /// Tag value used on propagation headers.
    public var tagValue: String {
        switch self {
        case .fallback:  "0"
        case .agentRate: "1"
        case .manual:    "4"
        }
    }

    /// Creates a ``SamplingMechanismType`` from a tag value used on propagation headers.
    ///
    /// - Note: Do not include the `-` character in the tag, since that character is a separator and
    /// not part of the tag itself.
    init?(tagValue: String) {
        switch tagValue {
        case "0": self = .fallback
        case "1": self = .agentRate
        case "4": self = .manual
        default: return nil
        }
    }
}
