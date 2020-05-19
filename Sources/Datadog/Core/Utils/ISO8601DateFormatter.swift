/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

@available(OSX 10.12, *)
extension ISO8601DateFormatter {
    static func `default`() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        if #available(OSX 10.13, *) {
            formatter.formatOptions.insert(.withFractionalSeconds)
        }
        return formatter
    }

    static var encodingStrategy: JSONEncoder.DateEncodingStrategy {
        let formatter = Self.default()
        return .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatted = formatter.string(from: date)
            try container.encode(formatted)
        }
    }
}

/// Fallback for older macOS versions
func iso8601DateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter
}
