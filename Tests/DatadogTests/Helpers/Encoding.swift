/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension EncodableValue: Equatable {
    public static func == (lhs: EncodableValue, rhs: EncodableValue) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

/// Prior to `iOS13.0`, the `JSONEncoder` supports only object or array as the root type.
/// Hence we can't test encoding `Encodable` values directly and we need as support of this `EncodingContainer` container.
///
/// Reference: https://bugs.swift.org/browse/SR-6163
struct EncodingContainer<Value: Encodable>: Encodable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
