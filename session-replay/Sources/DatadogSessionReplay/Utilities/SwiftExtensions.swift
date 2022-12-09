/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension FixedWidthInteger {
    /// Converts floating point value to fixed width integer with preventing overflow (and crash).
    /// In case of overflow, the value is converted to `.min` or `.max` respectively to its sign.
    /// - Parameter floatingPoint: the value to convert
    init<T: BinaryFloatingPoint>(withNoOverflow floatingPoint: T) {
        if let converted = Self(exactly: floatingPoint.rounded()) {
            self = converted
        } else { // overflow occured
            switch floatingPoint.sign {
            case .minus: self = .min
            case .plus: self = .max
            }
        }
    }
}

extension TimeInterval {
    /// `TimeInterval` represented in milliseconds (capped to `Int64.max`).
    var toInt64Milliseconds: Int64 {
        let miliseconds = self * 1_000
        return Int64(withNoOverflow: miliseconds)
    }
}
