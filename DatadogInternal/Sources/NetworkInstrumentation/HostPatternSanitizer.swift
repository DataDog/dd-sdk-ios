/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal func sanitizeHostPatterns(
    _ patterns: [String: Set<TracingHeaderType>],
    warningMessage: String
) -> [String: Set<TracingHeaderType>] {
    var warnings: [String] = []

    let sanitized = patterns.reduce(into: [String: Set<TracingHeaderType>]()) { result, item in
        let lowercased = item.key.lowercased()
        guard !lowercased.isEmpty else {
            warnings.append("'\(item.key)' is not a valid host pattern and will be dropped.")
            return
        }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-*")
        guard lowercased.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            warnings.append("'\(item.key)' is not a valid host pattern and will be dropped.")
            return
        }
        let wildcardCount = lowercased.filter({ $0 == "*" }).count
        guard wildcardCount <= 1 else {
            warnings.append("'\(item.key)' is not a valid host pattern and will be dropped.")
            return
        }
        guard wildcardCount == 0 || lowercased.contains(".") else {
            warnings.append("'\(item.key)' is not a valid host pattern and will be dropped.")
            return
        }
        result[lowercased] = item.value
    }

    warnings.forEach { warning in
        consolePrint(
            """
            ⚠️ \(warningMessage): \(warning)
            """,
            .warn
        )
    }

    return sanitized
}
