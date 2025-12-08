/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Protocol defining the interface for evaluating feature flags.
///
/// This protocol provides methods for setting the evaluation context and retrieving flag values
/// with detailed evaluation information. The protocol is extended with convenience methods for
/// common flag types.
public protocol FlagsClientProtocol: AnyObject {
    /// Sets the evaluation context for flag targeting.
    ///
    /// The evaluation context includes user or session information used to determine which flag
    /// variations are returned. Call this method before evaluating flags to ensure proper targeting.
    ///
    /// This method fetches flag assignments from the server asynchronously. The completion handler
    /// is called when the operation completes or fails.
    ///
    /// ```swift
    /// client.setEvaluationContext(
    ///     FlagsEvaluationContext(
    ///         targetingKey: "user-123",
    ///         attributes: [
    ///             "email": .string("user@example.com"),
    ///             "plan": .string("premium")
    ///         ]
    ///     )
    /// ) { result in
    ///     switch result {
    ///     case .success:
    ///         print("Context set successfully")
    ///     case .failure(let error):
    ///         print("Failed to set context: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - context: The evaluation context containing targeting key and custom attributes.
    ///   - completion: A closure called when the operation completes, receiving a `Result` indicating success or failure.
    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    )

    /// Evaluates a feature flag and returns detailed information about the evaluation.
    ///
    /// Use this method when you need access to evaluation metadata such as variant keys, reasons,
    /// or error information. For simple value access, use the convenience methods like
    /// ``getBooleanValue(key:defaultValue:)`` instead.
    ///
    /// ```swift
    /// let details = client.getDetails(key: "button-color", defaultValue: "blue")
    /// print("Value: \(details.value)")
    /// print("Variant: \(details.variant ?? "default")")
    /// if let error = details.error {
    ///     print("Evaluation error: \(error)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: A ``FlagDetails`` struct containing the evaluated value and metadata.
    func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue

    /// Note: This is an internal method. Expect breaking changes in the future.
    @_spi(Internal)
    func getAllFlagsDetails() -> [String: FlagDetails<AnyValue>]?

    /// Note: This is an internal method. Expect breaking changes in the future.
    @_spi(Internal)
    func trackEvaluation(key: String)
}

extension FlagsClientProtocol {
    /// Sets the evaluation context without waiting for completion.
    ///
    /// This is a convenience method that calls ``setEvaluationContext(_:completion:)`` without
    /// a completion handler. Use this when you don't need to be notified of success or failure.
    ///
    /// ```swift
    /// client.setEvaluationContext(
    ///     FlagsEvaluationContext(targetingKey: "user-123")
    /// )
    /// ```
    ///
    /// - Parameter context: The evaluation context containing targeting key and custom attributes.
    @inlinable
    public func setEvaluationContext(_ context: FlagsEvaluationContext) {
        setEvaluationContext(context, completion: { _ in })
    }

    /// Sets the evaluation context for flag targeting asynchronously.
    ///
    /// This method fetches flag assignments from the server and suspends until the operation completes.
    /// Use this async/await version when working in an async context.
    ///
    /// ```swift
    /// do {
    ///     try await client.setEvaluationContext(
    ///         FlagsEvaluationContext(
    ///             targetingKey: "user-123",
    ///             attributes: [
    ///                 "email": .string("user@example.com"),
    ///                 "plan": .string("premium")
    ///             ]
    ///         )
    ///     )
    ///     // Context set successfully
    /// } catch {
    ///     print("Failed to set context: \(error)")
    /// }
    /// ```
    ///
    /// - Parameter context: The evaluation context containing targeting key and custom attributes.
    ///
    /// - Throws: ``FlagsError`` if the operation fails.
    @available(iOS 13.0, tvOS 13.0, *)
    public func setEvaluationContext(_ context: FlagsEvaluationContext) async throws {
        try await withCheckedThrowingContinuation { continuation in
            setEvaluationContext(context) { result in
                continuation.resume(with: result)
            }
        }
    }
}

// MARK: - Convenience flag evaluation methods

extension FlagsClientProtocol {
    /// Evaluates a feature flag and returns only its value.
    ///
    /// This is a convenience method that evaluates a flag and returns only the value,
    /// discarding evaluation metadata. Use ``getDetails(key:defaultValue:)`` if you need
    /// access to variant, reason, or error information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: The evaluated flag value, or `defaultValue` if evaluation fails.
    @inlinable
    public func getValue<T>(key: String, defaultValue: T) -> T where T: Equatable, T: FlagValue {
        getDetails(key: key, defaultValue: defaultValue).value
    }

    /// Evaluates a boolean feature flag.
    ///
    /// ```swift
    /// let isEnabled = client.getBooleanValue(key: "new-feature-enabled", defaultValue: false)
    /// ```
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: The evaluated boolean value.
    @inlinable
    public func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        getValue(key: key, defaultValue: defaultValue)
    }

    /// Evaluates a string feature flag.
    ///
    /// ```swift
    /// let theme = client.getStringValue(key: "app-theme", defaultValue: "light")
    /// ```
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: The evaluated string value.
    @inlinable
    public func getStringValue(key: String, defaultValue: String) -> String {
        getValue(key: key, defaultValue: defaultValue)
    }

    /// Evaluates an integer feature flag.
    ///
    /// ```swift
    /// let maxRetries = client.getIntegerValue(key: "max-retries", defaultValue: 3)
    /// ```
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: The evaluated integer value.
    @inlinable
    public func getIntegerValue(key: String, defaultValue: Int) -> Int {
        getValue(key: key, defaultValue: defaultValue)
    }

    /// Evaluates a double feature flag.
    ///
    /// ```swift
    /// let timeout = client.getDoubleValue(key: "request-timeout", defaultValue: 30.0)
    /// ```
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: The evaluated double value.
    @inlinable
    public func getDoubleValue(key: String, defaultValue: Double) -> Double {
        getValue(key: key, defaultValue: defaultValue)
    }

    /// Evaluates a JSON object feature flag.
    ///
    /// Use this method for complex configuration values that contain structured data.
    ///
    /// ```swift
    /// let config = client.getObjectValue(
    ///     key: "api-config",
    ///     defaultValue: .dictionary(["endpoint": .string("https://api.example.com")])
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: The evaluated ``AnyValue`` object.
    @inlinable
    public func getObjectValue(key: String, defaultValue: AnyValue) -> AnyValue {
        getValue(key: key, defaultValue: defaultValue)
    }
}

// MARK: - Convenience flag details methods

extension FlagsClientProtocol {
    /// Evaluates a boolean feature flag with detailed evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: A ``FlagDetails`` value containing the boolean value and metadata.
    @inlinable
    public func getBooleanDetails(key: String, defaultValue: Bool) -> FlagDetails<Bool> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    /// Evaluates a string feature flag with detailed evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: A ``FlagDetails`` value containing the string value and metadata.
    @inlinable
    public func getStringDetails(key: String, defaultValue: String) -> FlagDetails<String> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    /// Evaluates an integer feature flag with detailed evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: A ``FlagDetails`` value containing the integer value and metadata.
    @inlinable
    public func getIntegerDetails(key: String, defaultValue: Int) -> FlagDetails<Int> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    /// Evaluates a double feature flag with detailed evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: A ``FlagDetails`` value containing the double value and metadata.
    @inlinable
    public func getDoubleDetails(key: String, defaultValue: Double) -> FlagDetails<Double> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    /// Evaluates a JSON object feature flag with detailed evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key to evaluate.
    ///   - defaultValue: The value to return if the flag is not found or evaluation fails.
    ///
    /// - Returns: A ``FlagDetails`` value containing the ``AnyValue`` object and metadata.
    @inlinable
    public func getObjectDetails(key: String, defaultValue: AnyValue) -> FlagDetails<AnyValue> {
        getDetails(key: key, defaultValue: defaultValue)
    }
}
