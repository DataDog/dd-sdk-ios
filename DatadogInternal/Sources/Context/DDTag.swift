/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Shared key names used in `ddTags` strings across the SDK.
public enum DDTag {
    public static let service = "service"
    public static let version = "version"
    public static let sdkVersion = "sdk_version"
    public static let env = "env"
    public static let variant = "variant"

    /// Merges two `ddTags` strings by key, e.g. `"service:app,env:prod"`.
    ///
    /// If a key exists in both `lhs` and `rhs`, the value from `rhs` takes precedence.
    ///
    /// - Parameters:
    ///   - lhs: The base `ddTags` string.
    ///   - rhs: The `ddTags` string to merge on top of `lhs`, if any.
    /// - Returns: The merged `ddTags` string.
    public static func merge(_ lhs: String, with rhs: String?) -> String {
        guard let rhs, !rhs.isEmpty else {
            return lhs
        }

        return parse(lhs)
            .merging(parse(rhs)) { $1 }
            .map { "\($0.key):\($0.value)" }
            .sorted()
            .joined(separator: ",")
    }

    private static func parse(_ tags: String) -> [String: String] {
        tags
            .split(separator: ",")
            .compactMap { tag -> (key: String, value: String)? in
                let keyValue = tag.split(separator: ":", maxSplits: 1)
                guard keyValue.count == 2 else {
                    return nil
                }
                return (key: String(keyValue[0]), value: String(keyValue[1]))
            }
            .reduce(into: [:]) { result, tag in
                result[tag.key] = String(tag.value)
            }
    }
}
