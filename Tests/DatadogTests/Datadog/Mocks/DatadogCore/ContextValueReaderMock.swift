/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal class ContextValueReaderMock<Value>: ContextValueReader {
    let initialValue: Value

    var value: Value

    init(initialValue: Value) {
        self.initialValue = initialValue
        self.value = initialValue
    }

    init() where Value: ExpressibleByNilLiteral {
        initialValue = nil
        value = nil
    }

    func read(to receiver: inout Value) {
        receiver = value
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
