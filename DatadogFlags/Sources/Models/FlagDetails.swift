/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public enum FlagEvaluationError: Error {
    case invalidClient
    case flagNotFound
    case typeMismatch
}

public struct FlagDetails<T>: Equatable where T: Equatable {
    public var key: String
    public var value: T
    public var variant: String?
    public var reason: String?
    public var error: FlagEvaluationError?

    public init(
        key: String,
        value: T,
        variant: String? = nil,
        reason: String? = nil,
        error: FlagEvaluationError? = nil
    ) {
        self.key = key
        self.value = value
        self.variant = variant
        self.reason = reason
        self.error = error
    }
}
