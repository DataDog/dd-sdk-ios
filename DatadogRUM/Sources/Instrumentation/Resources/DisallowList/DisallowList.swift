/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A struct that represents the disallow-list of URL patterns excluded from RUM resource tracking, configured via
/// `RUM.Configuration.URLSessionTracking.disallowList`.
///
/// A plain string matches the URL exactly, while a string containing a single `*` is compiled into a wildcard
/// match. Patterns with more than one `*` are invalid and dropped with a warning.
internal struct DisallowList {
    private let patterns: [String]

    var isEmpty: Bool { patterns.isEmpty }

    init(_ patterns: [String]) {
        self.patterns = patterns.compactMap { pattern in
            switch pattern.filter({ $0 == "*" }).count {
            case 0:
                return "^" + NSRegularExpression.escapedPattern(for: pattern) + "$"
            case 1 where pattern != "*":
                let parts = pattern.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                return "^" + NSRegularExpression.escapedPattern(for: parts[0]) + ".*" + NSRegularExpression.escapedPattern(for: parts[1]) + "$"
            default:
                DD.logger.warn("The disallow-list pattern '\(pattern)' is not valid and will be ignored.")
                return nil
            }
        }
    }

    func isDisallowed(url: URL?) -> Bool {
        guard let url = url, !patterns.isEmpty else {
            return false
        }
        let urlString = url.absoluteString
        return patterns.contains { urlString.range(of: $0, options: .regularExpression) != nil }
    }
}
