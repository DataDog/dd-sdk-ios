/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public protocol FlagsClientProtocol {
    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    )

    func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue
}

// MARK: - Convenience flag evaluation methods

extension FlagsClientProtocol {
    @inlinable
    public func getValue<T>(key: String, defaultValue: T) -> T where T: Equatable, T: FlagValue {
        getDetails(key: key, defaultValue: defaultValue).value
    }

    @inlinable
    public func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getStringValue(key: String, defaultValue: String) -> String {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getIntegerValue(key: String, defaultValue: Int) -> Int {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getDoubleValue(key: String, defaultValue: Double) -> Double {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getObjectValue(key: String, defaultValue: AnyValue) -> AnyValue {
        getValue(key: key, defaultValue: defaultValue)
    }
}

// MARK: - Convenience flag details methods

extension FlagsClientProtocol {
    @inlinable
    public func getBooleanDetails(key: String, defaultValue: Bool) -> FlagDetails<Bool> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getStringDetails(key: String, defaultValue: String) -> FlagDetails<String> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getIntegerDetails(key: String, defaultValue: Int) -> FlagDetails<Int> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getDoubleDetails(key: String, defaultValue: Double) -> FlagDetails<Double> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getObjectDetails(key: String, defaultValue: AnyValue) -> FlagDetails<AnyValue> {
        getDetails(key: key, defaultValue: defaultValue)
    }
}

// MARK: - NOPFlagsClient

internal final class NOPFlagsClient: FlagsClientProtocol {
    func setEvaluationContext(
        _: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        warn()
        completion(.failure(.clientNotInitialized))
    }

    func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue {
        warn()
        return FlagDetails(key: key, value: defaultValue)
    }

    private func warn(method: StaticString = #function) {
        DD.logger.critical(
            """
            Calling `\(method)` on NOPFlagsClient.
            Make sure Flags feature is enabled and that the `FlagsClient` was created successfully.
            """
        )
    }
}
