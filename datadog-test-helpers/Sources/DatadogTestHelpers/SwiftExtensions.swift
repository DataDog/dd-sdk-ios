/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import Foundation

public extension Data {
    func toArrayOfJSONObjects(file: StaticString = #file, line: UInt = #line) throws -> [[String: Any]] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: self, options: []) as? [[String: Any]] else {
            XCTFail("Cannot decode array of JSON objects from data.", file: file, line: line)
            return []
        }

        return jsonArray
    }

    func toJSONObject(file: StaticString = #file, line: UInt = #line) throws -> [String: Any] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: self, options: []) as? [String: Any] else {
            XCTFail("Cannot decode JSON object from given data.", file: file, line: line)
            return [:]
        }

        return jsonObject
    }
}

public extension Date {
    func isNotOlderThan(seconds: TimeInterval) -> Bool {
        return Date().timeIntervalSince(self) <= seconds
    }
}
