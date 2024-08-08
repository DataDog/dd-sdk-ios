/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension URL {

    var components: URLComponents? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)
    }

    /// Appends query items to the URL.
    /// - Parameter queryItems: The query items to append.
    public mutating func append(_ queryItems: [URLQueryItem]) {
        guard var components = self.components else {
            return
        }
        components.queryItems = (components.queryItems ?? []) + queryItems

        guard let url = components.url else {
            return
        }

        self = url
    }

    /// Appends a query item to the URL.
    /// - Parameter queryItem: The query item to append.
    public mutating func append(_ queryItem: URLQueryItem) {
        append([queryItem])
    }


    /// Returns the first query item with the given name.
    /// - Parameter name: The name of the query item to return.
    /// - Returns: The first query item with the given name, or `nil` if no such query item exists.
    public func queryItem(_ name: String) -> URLQueryItem? {
        guard let components = self.components else {
            return nil
        }

        return components.queryItems?.first { $0.name == name }
    }


    /// Removes a query item from the URL.
    /// - Parameter name: The name of the query item to remove.
    public mutating func removeQueryItem(name: String) {
        guard var components = self.components else {
            return
        }

        components.queryItems = components.queryItems?.filter { $0.name != name }

        // this allows to remove the query separator (?) if there are no query items left
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }

        guard let url = components.url else {
            return
        }

        self = url
    }
}
