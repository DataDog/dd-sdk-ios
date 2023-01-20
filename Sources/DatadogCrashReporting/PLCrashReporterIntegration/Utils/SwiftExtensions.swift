/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal extension UInt64 {
    /// Returns the difference obtained by subtracting the given value from this value only if
    /// it doesn't overflow (otherwise it returns `nil`).
    func subtractIfNoOverflow(_ otherUInt64: UInt64) -> UInt64? {
        let (partialValue, overflow) = subtractingReportingOverflow(otherUInt64)
        return overflow ? nil : partialValue
    }

    /// Returns the sum of this value and the given value only if it doesn't overflow (otherwise it returns `nil`).
    func addIfNoOverflow(_ otherUInt64: UInt64) -> UInt64? {
        let (partialValue, overflow) = addingReportingOverflow(otherUInt64)
        return overflow ? nil : partialValue
    }

    /// Returns hexadecimal representation of this value.
    var toHex: String { String(self, radix: 16, uppercase: false) }
}

internal extension String {
    func addPrefix(repeating character: Character, targetLength: Int) -> String {
        let prefix = String(repeating: character, count: max(0, targetLength - count))
        return "\(prefix)\(self)"
    }

    func addSuffix(repeating character: Character, targetLength: Int) -> String {
        let suffix = String(repeating: character, count: max(0, targetLength - count))
        return "\(self)\(suffix)"
    }
}
