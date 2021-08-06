/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal typealias EncodableValue = CodableValue
internal typealias DecodableValue = CodableValue

/// Helper type performing type erasure of encoded JSON types.
/// It conforms to `Encodable`, so decoded value can be further serialized into exactly the same JSON representation.
internal struct CodableValue: Codable {
    struct CodableNull: Encodable {}

    let value: Encodable

    init(_ value: Encodable) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self.init(bool)
        } else if let uint64 = try? container.decode(UInt64.self) {
            self.init(uint64)
        } else if let int = try? container.decode(Int.self) {
            self.init(int)
        } else if let double = try? container.decode(Double.self) {
            self.init(double)
        } else if let string = try? container.decode(String.self) {
            self.init(string)
        } else if let array = try? container.decode([CodableValue].self) {
            self.init(array)
        } else if let dictionary = try? container.decode([String: CodableValue].self) {
            self.init(dictionary)
        } else if container.decodeNil() {
            self.init(CodableNull())
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Custom attribute at \(container.codingPath) is not a `Codable` type supported by the SDK."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        if let urlValue = value as? URL {
            /**
             "URL itself prefers a keyed container which allows it to encode its base and relative string separately (...)"
             Discussion: https:forums.swift.org/t/how-to-encode-objects-of-unknown-type/12253/11

             It means that following code:
             ```
             try EncodableValue(URL(string: "https:example.com")!).encode(to: encoder)
             ```
             encodes the KVO representation of the URL: `{"relative":"https:example.com"}`.
             As we very much prefer `"https:example.com"`, here we switch to encode `.absoluteString` directly.
             */
            try urlValue.absoluteString.encode(to: encoder)
        } else if value is CodableNull {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        } else {
            try value.encode(to: encoder)
        }
    }
}
