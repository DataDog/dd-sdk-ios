/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class FlagsEvaluationContext {
    public let targetingKey: String
    public let attributes: [String: Any]
    
    public init(targetingKey: String, attributes: [String: Any] = [:]) {
        self.targetingKey = targetingKey
        self.attributes = attributes
    }
}

public enum FlagsError: Error {
    case networkError(Error)
    case invalidResponse
    case clientNotInitialized
    case invalidConfiguration
    case unsupportedSite(String)
}

internal struct FlagsMetadata {
    let fetchedAt: Double // Timestamp in milliseconds (JavaScript-style)
    let context: FlagsEvaluationContext?
}
