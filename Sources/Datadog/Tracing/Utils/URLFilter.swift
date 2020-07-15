/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol URLFiltering {
    func allows(_ url: URL?) -> Bool
}

internal struct URLFilter: URLFiltering, Equatable {
    private let excludedURLs: Set<String>
    private let inclusionRegex: String

    init(includedHosts: Set<String>, excludedURLs: Set<String>) {
        self.inclusionRegex = Self.buildRegexString(from: includedHosts)
        self.excludedURLs = excludedURLs
    }

    func allows(_ url: URL?) -> Bool {
        guard !excludes(url),
            let host = url?.host else {
                return false
        }
        let isIncluded = host.range(of: inclusionRegex, options: .regularExpression) != nil
        return isIncluded
    }

    private func excludes(_ url: URL?) -> Bool {
        if let absoluteString = url?.absoluteString {
            return excludedURLs.contains {
                absoluteString.starts(with: $0)
            }
        }
        return true
    }

    /// matches hosts and their subdomains: example.com -> example.com, api.example.com, sub.example.com, etc.
    private static func buildRegexString(from hosts: Set<String>) -> String {
        return hosts.map {
            let escaped = NSRegularExpression.escapedPattern(for: $0)
            /// pattern = "^(.*\\.)*tracedHost1|^(.*\\.)*tracedHost2|..."
            return "^(.*\\.)*\(escaped)$"
        }
        .joined(separator: "|")
    }
}
