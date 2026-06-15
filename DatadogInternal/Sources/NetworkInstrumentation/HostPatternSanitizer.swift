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
    let wildcardPatterns = patterns.filter { $0.key.contains("*") }
    let plainPatterns = patterns.filter { !$0.key.contains("*") }

    let sanitizedPlain = HostsSanitizer().sanitized(
        hostsWithTracingHeaderTypes: plainPatterns,
        warningMessage: warningMessage
    )

    var warnings: [String] = []
    let sanitizedWildcard = wildcardPatterns.reduce(into: [String: Set<TracingHeaderType>]()) { result, item in
        guard let lowercased = validatedWildcardPattern(item.key, collectingWarningsInto: &warnings) else {
            return
        }
        result[lowercased] = item.value
    }
    emitPatternWarnings(warnings, warningMessage: warningMessage)

    return sanitizedPlain.merging(sanitizedWildcard) { $0.union($1) }
}

public func sanitizeHostPatterns(_ patterns: [String], warningMessage: String) -> [String] {
    let wildcardPatterns = patterns.filter { $0.contains("*") }
    let plainPatterns = Set(patterns.filter { !$0.contains("*") })

    let sanitizedPlain = HostsSanitizer().sanitized(hosts: plainPatterns, warningMessage: warningMessage)

    var warnings: [String] = []
    let sanitizedWildcard = wildcardPatterns.compactMap { validatedWildcardPattern($0, collectingWarningsInto: &warnings) }
    emitPatternWarnings(warnings, warningMessage: warningMessage)

    return Array(sanitizedPlain) + sanitizedWildcard
}

private func validatedWildcardPattern(_ pattern: String, collectingWarningsInto warnings: inout [String]) -> String? {
    let lowercased = pattern.lowercased()
    let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-*")
    guard lowercased.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
        warnings.append("'\(pattern)' is not a valid host pattern and will be dropped.")
        return nil
    }
    guard lowercased.filter({ $0 == "*" }).count == 1 else {
        warnings.append("'\(pattern)' is not a valid host pattern and will be dropped.")
        return nil
    }
    guard lowercased.contains(".") else {
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
