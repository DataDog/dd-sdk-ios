/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore

public class ContextValuePublisherMock<Value>: ContextValuePublisher {
    private let queue = DispatchQueue(
        label: "com.datadoghq.context-value-publisher-mock"
    )

    public let initialValue: Value

    public var value: Value {
        get { queue.sync { _value } }
        set { queue.sync { _value = newValue } }
    }

    private var receiver: ContextValueReceiver<Value>?
    private var _value: Value {
        didSet { receiver?(_value) }
    }

    public init(initialValue: Value) {
        self.initialValue = initialValue
        self._value = initialValue
    }

    public init() where Value: ExpressibleByNilLiteral {
        initialValue = nil
        _value = nil
    }

    public func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        queue.sync { self.receiver = receiver }
    }

    public func cancel() {
        queue.sync { receiver = nil }
    }
}

extension ContextValuePublisher {
    public static func mockAny() -> ContextValuePublisherMock<Value> where Value: ExpressibleByNilLiteral {
        .init()
    }

    public static func mockWith(initialValue: Value) -> ContextValuePublisherMock<Value> {
        .init(initialValue: initialValue)
    }
}
