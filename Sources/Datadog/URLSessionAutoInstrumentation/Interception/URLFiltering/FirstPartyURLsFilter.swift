/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Filters `URLs` which match the first party hosts given by the user.
internal struct FirstPartyURLsFilter {
    /// A regexp for matching hosts, e.g. when `hosts` is "example.com", it will match
    /// "example.com", "api.example.com", but not "foo.com".
    private let regex: String?

    init(hosts: Set<String>) {
        if hosts.isEmpty {
            self.regex = nil
        } else {
            // pattern = "^(.*\\.)*tracedHost1$|tracedHost2$|...$"
            let escapedHosts = hosts
                .map { "\(NSRegularExpression.escapedPattern(for: $0))$" }
                .joined(separator: "|")
            self.regex = "^(.*\\.)*\(escapedHosts)"
        }
    }

    /// Returns `true` if given `URL` matches the first party hosts defined by the user; `false` otherwise.
    func isFirstParty(url: URL?) -> Bool {
        guard let regex = self.regex,
              let host = url?.host else {
            return false
        }
        return host.range(of: regex, options: .regularExpression) != nil
    }

    // Returns `true` if given `String` can be parsed as a URL and matches the first
    // party hosts defined by the user; `false` otherwise
    func isFirstParty(string: String) -> Bool {
        guard let url = URL(string: string),
              let regex = self.regex,
              let host = url.host else {
            return false
        }
        return host.range(of: regex, options: .regularExpression) != nil
    }
}
