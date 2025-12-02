/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Details of the request send to the Python server.
public struct Request {
    /// Original path of this request.
    public let path: String
    /// Query params of this request.
    public let queryItems: [URLQueryItem]?
    /// HTTP method of this request.
    public let httpMethod: String
    /// HTTP headers associated with this request.
    public let httpHeaders: [String: String]
    /// HTTP body of this request.
    public let httpBody: Data
}

extension Array where Element == URLQueryItem {
    /// Returns the `ddtags` query item as a dictionary.
    /// The `ddtags` query item is expected to be in the format `key:value,key:value`.
    /// - Returns: The `ddtags` query item as a dictionary.
    public func ddtags() -> [String: String]? {
        guard let ddtags = first(where: { $0.name == "ddtags" })?.value else {
            return nil
        }
        return ddtags.split(separator: ",", keyValueSeparator: ":")
    }

    /// Returns the value of the first query item with the given name.
    /// - Parameter name: The name of the query item to return.
    /// - Returns: The value of the first query item with the given name, or `nil` if no such query item exists.
    public func value(name: String) -> String? {
        first(where: { $0.name == name })?.value
    }

    /// Returns the values of all query items with the given name.
    /// - Parameter name: The name of the query items to return.
    /// - Returns: The values of all query items with the given name. If no such query item exists, an empty array is returned.
    public func values(name: String) -> [String?] {
        filter { $0.name == name }.map { $0.value }
    }
}

extension String {
    /// Splits the string into a dictionary.
    /// - Parameters:
    ///   - separator: Separator to split the string.
    ///   - keyValueSeparator: Separator to split the key and value.
    /// - Returns: The string as a dictionary. If the string is not in the expected format, an empty dictionary is returned.
    public func split(separator: String, keyValueSeparator: String) -> [String: String] {
        let components = self.components(separatedBy: separator)
        var result: [String: String] = [:]
        components.forEach { header in
            let components = header.components(separatedBy: keyValueSeparator)
            if let field = components.first {
                let value = components.dropFirst().joined(separator: keyValueSeparator)
                result[field] = value
            }
        }
        return result
    }
}
