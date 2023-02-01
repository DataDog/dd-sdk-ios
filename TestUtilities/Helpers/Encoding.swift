/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Prior to `iOS13.0`, the `JSONEncoder` supports only object or array as the root type.
/// Hence we can't test encoding `Encodable` values directly and we need to wrap it inside this `EncodingContainer` container.
///
/// Reference: https://bugs.swift.org/browse/SR-6163
public struct EncodingContainer<Value: Encodable>: Encodable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}
