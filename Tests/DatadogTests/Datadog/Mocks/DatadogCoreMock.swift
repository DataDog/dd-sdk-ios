/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal final class DatadogCoreMock: DatadogCoreProtocol, Flushable {
    private var v1Features: [String: Any] = [:]
    private var v1Context: DatadogV1Context

    init(v1Context: DatadogV1Context = .mockAny()) {
        self.v1Context = v1Context
    }

    /// Flush resgistered features.
    ///
    /// The method will also call `flush` on any `Flushable` registered
    /// feature.
    func flush() {
        all(Flushable.self).forEach { $0.flush() }
        v1Features = [:]
    }

    /// Gets all registered feature of a given type.
    ///
    /// - Parameter type: The desired feature type.
    /// - Returns: Array of feature.
    func all<T>(_ type: T.Type) -> [T] {
        v1Features.values.compactMap { $0 as? T }
    }

    // MARK: V1 interface

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        v1Features[key] = instance
    }

    func feature<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return v1Features[key] as? T
    }

    var context: Any {
        return v1Context
    }
}

/// `Flushable` object resets its state on flush.
///
/// Calling `flush` method should reset any in-memory and persistent
/// data to initialised state.
internal protocol Flushable {
    /// Flush data and reset state.
    func flush()
}

extension LoggingFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension TracingFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension RUMFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension RUMInstrumentation: Flushable {
    func flush() {
        deinitialize()
    }
}

extension URLSessionAutoInstrumentation: Flushable {
    func flush() {
        deinitialize()
    }
}

extension DatadogV1Context: AnyMockable {
    static func mockAny() -> DatadogV1Context {
        return mockWith()
    }

    static func mockWith(
        configuration: CoreConfiguration = .mockAny(),
        dependencies: CoreDependencies = .mockAny()
    ) -> DatadogV1Context {
        return DatadogV1Context(
            configuration: configuration,
            dependencies: dependencies
        )
    }
}
