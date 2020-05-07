/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Type erasure `Encodable` wrapper. 
internal struct EncodableValue: Encodable {
    let value: Encodable

    init(_ value: Encodable) {
        self.value = value
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
        } else {
            try value.encode(to: encoder)
        }
    }
}

/// Value type converting any `Encodable` to its lossless JSON string representation.
///
/// For example:
/// * it encodes `"abc"` string as `"abc"` JSON string value
/// * it encodes `1` integer as `"1"` JSON string value
/// * it encodes `true` boolean as `"true"` JSON string value
/// * it encodes `Person(name: "foo")` encodable struct as `"{\"name\": \"foo\"}"` JSON string value
///
/// This encoding doesn't happen instantly. Instead, it is deferred to the actual `encoder.encode(jsonStringEncodableValue)` call.
internal struct JSONStringEncodableValue: Encodable {
    /// Encoder used to encode `encodable` as JSON String value.
    /// It is invoked lazily at `encoder.encode(jsonStringEncodableValue)` so its encoding errors can be propagated in master-type encoding.
    private let jsonEncoder: JSONEncoder
    private let encodable: EncodableValue

    init(_ value: Encodable, encodedUsing jsonEncoder: JSONEncoder) {
        self.jsonEncoder = jsonEncoder
        self.encodable = EncodableValue(value)
    }

    func encode(to encoder: Encoder) throws {
        if let stringValue = encodable.value as? String {
            try stringValue.encode(to: encoder)
        } else if let urlValue = encodable.value as? URL {
            // Switch to encode `url.absoluteString` directly - see the comment in `EncodableValue`
            try urlValue.absoluteString.encode(to: encoder)
        } else {
            let jsonData = try jsonEncoder.encode(encodable)
            if let stringValue = String(data: jsonData, encoding: .utf8) {
                try stringValue.encode(to: encoder)
            }
        }
    }
}
