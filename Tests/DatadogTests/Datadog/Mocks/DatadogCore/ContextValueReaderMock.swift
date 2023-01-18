/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal class ContextValueReaderMock<Value>: ContextValueReader {
    private let queue = DispatchQueue(
        label: "com.datadoghq.context-value-reader-mock"
    )

    var value: Value {
        get { queue.sync { _value } }
        set { queue.sync { _value = newValue } }
    }

    private var _value: Value

    init(initialValue: Value) {
        self._value = initialValue
    }

    init() where Value: ExpressibleByNilLiteral {
        _value = nil
    }

    func read(to receiver: inout Value) {
        receiver = queue.sync { _value }
    }
}

extension ContextValueReader {
    static func mockAny() -> ContextValueReaderMock<Value> where Value: ExpressibleByNilLiteral {
        .init()
    }

    static func mockWith(initialValue: Value) -> ContextValueReaderMock<Value> {
        .init(initialValue: initialValue)
    }
}
