/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct AnyCodableError: Error {
    let description: String
}

/// An utility type which allows casting `Encodable` types to `Codable` interface with no support for decoding.
internal struct AnyCodable: Codable {
    let encodable: Encodable

    init(_ value: Any) {
        self.init(encodable: AnyEncodable(value))
    }

    init(encodable: Encodable) {
        self.encodable = encodable
    }

    init(from decoder: Decoder) throws {
        throw AnyCodableError(description: "`AnyCodable` doesn't support decoding.")
    }

    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}
