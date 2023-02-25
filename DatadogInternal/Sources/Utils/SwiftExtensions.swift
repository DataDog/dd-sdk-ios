/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// MARK: - Optional

extension Optional {
    public func ifNotNil(_ closure: (Wrapped) throws -> Void) rethrows {
        if case .some(let unwrappedValue) = self {
            try closure(unwrappedValue)
        }
    }
}

extension Double {
    public func divideIfNotZero(by divider: Self) -> Self? {
        if divider == 0 {
            return nil
        }
        return self / divider
    }

    public var inverted: Self {
        return self == 0 ? 0 : 1 / self
    }
}

// MARK: - UUID

extension UUID {
    /// An UUID with all zeroes (`00000000-0000-0000-0000-000000000000`).
    /// Used to represent "null" in types that cannot be given a proper UUID (e.g. rejected RUM session).
    public static let nullUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
}

// MARK: - TimeInterval

extension TimeInterval {
    public init(fromMilliseconds milliseconds: Int64) {
        self = Double(milliseconds) / 1_000
    }

    /// `TimeInterval` represented in milliseconds (capped to `.min` or `.max` respectively to its sign).
    public var toMilliseconds: UInt64 {
        let milliseconds = self * 1_000
        return UInt64(withNoOverflow: milliseconds)
    }

    /// `TimeInterval` represented in milliseconds (capped to `.min` or `.max` respectively to its sign).
    public var toInt64Milliseconds: Int64 {
        let miliseconds = self * 1_000
        return Int64(withNoOverflow: miliseconds)
    }

    /// `TimeInterval` represented in nanoseconds (capped to `.min` or `.max` respectively to its sign).
    /// Note: as `TimeInterval` yields sub-millisecond precision the nanoseconds precission will be lost.
    public var toNanoseconds: UInt64 {
        let nanoseconds = self * 1_000_000_000
        return UInt64(withNoOverflow: nanoseconds)
    }

    /// `TimeInterval` represented in nanoseconds (capped to `.min` or `.max` respectively to its sign).
    /// Note: as `TimeInterval` yields sub-millisecond precision the nanoseconds precission will be lost.
    public var toInt64Nanoseconds: Int64 {
        let nanoseconds = self * 1_000_000_000
        return Int64(withNoOverflow: nanoseconds)
    }
}

// MARK: - Safe floating point to integer conversion

public enum FixedWidthIntegerError<T: BinaryFloatingPoint>: Error {
    case overflow(overflowingValue: T)
}

extension FixedWidthInteger {
    /* NOTE: RUMM-182
     Self(:) is commonly used for conversion, however it fatalError() in case of conversion failure
     Self(exactly:) does the exact same thing internally yet it returns nil instead of fatalError()
     It is not trivial to guess if the conversion would fail or succeed, therefore we use Self(exactly:)
     so that we don't need to guess in order to save the app from crashing

     IMPORTANT: If you pass floatingPoint to Self(exactly:) without rounded(), it may return nil
     */
    public init<T: BinaryFloatingPoint>(withReportingOverflow floatingPoint: T) throws {
        guard let converted = Self(exactly: floatingPoint.rounded()) else {
            throw FixedWidthIntegerError<T>.overflow(overflowingValue: floatingPoint)
        }
        self = converted
    }

    /// Converts floating point value to fixed width integer with preventing overflow (and crash).
    /// In case of overflow, the value is converted to `.min` or `.max` respectively to its sign.
    /// - Parameter floatingPoint: the value to convert
    public init<T: BinaryFloatingPoint>(withNoOverflow floatingPoint: T) {
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

// MARK: - Array

extension Array {
    public subscript (safe index: Index) -> Element? {
        0 <= index && index < count ? self[index] : nil
    }
}
