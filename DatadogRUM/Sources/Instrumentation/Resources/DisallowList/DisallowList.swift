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
/// A plain string matches the URL exactly, while `*` matches any sequence of characters. A pattern may contain
/// multiple `*` wildcards (e.g. `https://example.com/api/*/operations/*`). Patterns with no literal content
/// (e.g. `*`) are invalid and dropped with a warning.
internal struct DisallowList {
    private let patterns: [String]

    var isEmpty: Bool { patterns.isEmpty }

    init(_ patterns: [String]) {
        self.patterns = patterns.compactMap { pattern in
            let segments = pattern.components(separatedBy: "*")
            // Reject patterns with no literal content (e.g. `*`, `**`) - they would disallow every URL.
            guard segments.contains(where: { !$0.isEmpty }) else {
                DD.logger.warn("The disallow-list pattern '\(pattern)' is not valid and will be ignored.")
                return nil
            }
            let escaped = segments.map { NSRegularExpression.escapedPattern(for: $0) }
            return "^" + escaped.joined(separator: ".*") + "$"
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
