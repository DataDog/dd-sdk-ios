/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal class ContextValuePublisherMock<Value>: ContextValuePublisher {
    private let queue = DispatchQueue(
        label: "com.datadoghq.context-value-publisher-mock"
    )

    let initialValue: Value

    var value: Value {
        get { queue.sync { _value } }
        set { queue.sync { _value = newValue } }
    }

    private var receiver: ContextValueReceiver<Value>?
    private var _value: Value {
        didSet { receiver?(_value) }
    }

    init(initialValue: Value) {
        self.initialValue = initialValue
        self._value = initialValue
    }

    init() where Value: ExpressibleByNilLiteral {
        initialValue = nil
        _value = nil
    }

    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        queue.sync { self.receiver = receiver }
    }

    func cancel() {
        queue.sync { receiver = nil }
    }
}

extension ContextValuePublisher {
    static func mockAny() -> ContextValuePublisherMock<Value> where Value: ExpressibleByNilLiteral {
        .init()
    }

    static func mockWith(initialValue: Value) -> ContextValuePublisherMock<Value> {
        .init(initialValue: initialValue)
    }
}
