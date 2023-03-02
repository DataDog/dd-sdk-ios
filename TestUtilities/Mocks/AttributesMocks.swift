/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Creates randomized `[String: Codable]` attributes
public func mockRandomAttributes() -> [String: Codable] {
    struct Foo: Codable {
        var bar: String = .mockRandom()
        var bizz = Bizz()

        struct Bizz: Codable {
            var buzz: String = .mockRandom()
        }
    }

    // Produces a `.none` value for optional of a random type.
    let randomAbsentOptional: () -> Codable = [
        // swiftlint:disable opening_brace syntactic_sugar
        { Optional<String>.none },
        { Optional<Int>.none },
        { Optional<UInt64>.none },
        { Optional<Double>.none },
        { Optional<Bool>.none },
        { Optional<[Int]>.none },
        { Optional<[String: Int]>.none },
        { Optional<URL>.none },
        { Optional<Foo>.none },
        // swiftlint:enable opening_brace syntactic_sugar
    ].randomElement()!

    return [
        "string-attribute": String.mockRandom(),
        "int-attribute": Int.mockRandom(),
        "uint64-attribute": UInt64.mockRandom(),
        "double-attribute": Double.mockRandom(),
        "bool-attribute": Bool.random(),
        "int-array-attribute": [Int].mockRandom(),
        "dictionary-attribute": [String: Int].mockRandom(),
        "url-attribute": URL.mockRandom(),
        "encodable-struct-attribute": Foo(),
        "absent-attribute": randomAbsentOptional() // when JSON-encoding: `"absent-attribute": null`
    ]
}
