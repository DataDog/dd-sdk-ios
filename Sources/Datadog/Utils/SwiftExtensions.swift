/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// MARK: - Optional

extension Optional {
    func ifNotNil(_ closure: (Wrapped) throws -> Void) rethrows {
        if case .some(let unwrappedValue) = self {
            try closure(unwrappedValue)
        }
    }
}

// MARK: - Date

extension Date {
    // NOTE: RUMM-182 counterpart of currentTimeMillis in Java
    // https://docs.oracle.com/javase/7/docs/api/java/lang/System.html#currentTimeMillis()
    var currentTimeMillis: UInt64 {
        do {
            let miliseconds = self.timeIntervalSince1970 * 1_000
            return try UInt64(withReportingOverflow: miliseconds)
        } catch {
            userLogger.error("🔥 Failed to convert timestamp: \(error)")
            developerLogger?.error("🔥 Failed to convert timestamp: \(error)")
            return UInt64.max
        }
    }
}

// MARK: - Safe floating point to integer conversion

internal enum FixedWidthIntegerError<T: BinaryFloatingPoint>: Error {
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
    init<T: BinaryFloatingPoint>(withReportingOverflow floatingPoint: T) throws {
        guard let converted = Self(exactly: floatingPoint.rounded()) else {
            throw FixedWidthIntegerError<T>.overflow(overflowingValue: floatingPoint)
        }
        self = converted
    }
}
