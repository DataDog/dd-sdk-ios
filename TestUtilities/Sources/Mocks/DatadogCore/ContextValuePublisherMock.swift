/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore

/// A mock `ContextValueSource` that lets tests push values through an `AsyncStream`.
public class ContextValueSourceMock<Value: Sendable>: ContextValueSource, @unchecked Sendable {
    public let initialValue: Value
    public let values: AsyncStream<Value>

    private let continuation: AsyncStream<Value>.Continuation

    public var value: Value {
        didSet { continuation.yield(value) }
    }

    public init(initialValue: Value) {
        self.initialValue = initialValue
        self._value = initialValue
        var cont: AsyncStream<Value>.Continuation!
        self.values = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    public init() where Value: ExpressibleByNilLiteral {
        self.initialValue = nil
        self._value = nil
        var cont: AsyncStream<Value>.Continuation!
        self.values = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    deinit {
        continuation.finish()
    }
}

extension ContextValueSource {
    public static func mockAny() -> ContextValueSourceMock<Value> where Value: ExpressibleByNilLiteral {
        .init()
    }

    public static func mockWith(initialValue: Value) -> ContextValueSourceMock<Value> {
        .init(initialValue: initialValue)
    }
}
