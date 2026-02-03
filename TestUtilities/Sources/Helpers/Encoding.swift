/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

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

public extension Encodable {
    /// Converts the encodable value to a JSON object.
    func toJSONObject(file: StaticString = #file, line: UInt = #line) throws -> [String: Any] {
        return try JSONEncoder().encode(self).toJSONObject(file: file, line: line)
    }

    /// Converts the encodable value to an array of JSON objects
    func toArrayOfJSONObjects(file: StaticString = #file, line: UInt = #line) throws -> [[String: Any]] {
        return try JSONEncoder().encode(self).toArrayOfJSONObjects(file: file, line: line)
    }
}

public extension Data {
    /// Converts the data to a JSON object.
    func toJSONObject(file: StaticString = #file, line: UInt = #line) throws -> [String: Any] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: self, options: []) as? [String: Any] else {
            XCTFail("Cannot decode JSON object from given data.", file: file, line: line)
            return [:]
        }

        return jsonObject
    }

    /// Converts the data to an array of JSON objects.
    func toArrayOfJSONObjects(file: StaticString = #file, line: UInt = #line) throws -> [[String: Any]] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: self, options: []) as? [[String: Any]] else {
            XCTFail("Cannot decode array of JSON objects from data.", file: file, line: line)
            return []
        }

        return jsonArray
    }
}
