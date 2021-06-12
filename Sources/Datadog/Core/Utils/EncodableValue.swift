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
