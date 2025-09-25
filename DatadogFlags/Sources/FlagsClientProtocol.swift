/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Protocol defining the interface for FlagsClient
public protocol FlagsClientProtocol: AnyObject {
    /// The name of this FlagsClient instance
    var name: String { get }
    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    )
    func getBooleanValue(key: String, defaultValue: Bool) -> Bool
    func getStringValue(key: String, defaultValue: String) -> String
    func getIntegerValue(key: String, defaultValue: Int64) -> Int64
    func getDoubleValue(key: String, defaultValue: Double) -> Double
    func getObjectValue(key: String, defaultValue: [String: Any]) -> [String: Any]
}

/// A no-operation implementation of FlagsClient that does nothing.
/// Used as a safe fallback when FlagsClient creation fails.
public final class NOPFlagsClient: FlagsClientProtocol {
    /// The name of this NOP client instance
    public let name: String

    public init(name: String = "nop") {
        self.name = name
    }

    /// no-op - returns failure
    public func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        completion(.failure(.clientNotInitialized))
    }

    /// no-op - returns default value
    public func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        return defaultValue
    }

    /// no-op - returns default value
    public func getStringValue(key: String, defaultValue: String) -> String {
        return defaultValue
    }

    /// no-op - returns default value
    public func getIntegerValue(key: String, defaultValue: Int64) -> Int64 {
        return defaultValue
    }

    /// no-op - returns default value
    public func getDoubleValue(key: String, defaultValue: Double) -> Double {
        return defaultValue
    }

    /// no-op - returns default value
    public func getObjectValue(key: String, defaultValue: [String: Any]) -> [String: Any] {
        return defaultValue
    }
}
