/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public func sanitizeHostPatterns(
    _ patterns: [String: Set<TracingHeaderType>],
    warningMessage: String
) -> [String: Set<TracingHeaderType>] {
    var warnings: [String] = []
    let sanitized = patterns.reduce(into: [String: Set<TracingHeaderType>]()) { result, item in
        guard let lowercased = validatedHostPattern(item.key, collectingWarningsInto: &warnings) else {
            return
        }
        result[lowercased] = item.value
    }
    emitPatternWarnings(warnings, warningMessage: warningMessage)
    return sanitized
}

public func sanitizeHostPatterns(_ patterns: [String], warningMessage: String) -> [String] {
    var warnings: [String] = []
    let sanitized = patterns.compactMap { validatedHostPattern($0, collectingWarningsInto: &warnings) }
    emitPatternWarnings(warnings, warningMessage: warningMessage)
    return sanitized
}

private func validatedHostPattern(_ pattern: String, collectingWarningsInto warnings: inout [String]) -> String? {
    let lowercased = pattern.lowercased()
    guard !lowercased.isEmpty else {
        warnings.append("'\(pattern)' is not a valid host pattern and will be dropped.")
        return nil
    }
    let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-*")
    guard lowercased.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
        warnings.append("'\(pattern)' is not a valid host pattern and will be dropped.")
        return nil
    }
    let wildcardCount = lowercased.filter({ $0 == "*" }).count
    guard wildcardCount <= 1 else {
        warnings.append("'\(pattern)' is not a valid host pattern and will be dropped.")
        return nil
    }
    guard wildcardCount == 0 || lowercased.contains(".") else {
        warnings.append("'\(pattern)' is not a valid host pattern and will be dropped.")
        return nil
    }
    return lowercased
}

private func emitPatternWarnings(_ warnings: [String], warningMessage: String) {
    warnings.forEach { warning in
        consolePrint(
            """
            ⚠️ \(warningMessage): \(warning)
            """,
            .warn
        )
    }
}
