/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Common representation of Swift `Error` used by different features.
public struct DDError: Equatable, Codable {
    /// Common error key encoding threads information in Crash Reporting.
    /// See "RFC - iOS Crash Reports Minimization" for more context.
    public static let threads = "error.threads"
    /// Common error key encoding binary images information in Crash Reporting.
    /// See "RFC - iOS Crash Reports Minimization" for more context.
    public static let binaryImages = "error.binary_images"
    /// Common error key encoding crash meta information in Crash Reporting.
    /// See "RFC - iOS Crash Reports Minimization" for more context.
    public static let meta = "error.meta"
    /// Common error key encoding boolean flag - `true` if any stack trace was truncated, otherwise `false`.
    /// See "RFC - iOS Crash Reports Minimization" for more context.
    public static let wasTruncated = "error.was_truncated"

    public let type: String
    public let message: String
    public let stack: String
    public let sourceType: String

    public init(type: String, message: String, stack: String, sourceType: String = "ios") {
        self.type = type
        self.message = message
        self.stack = stack
        self.sourceType = sourceType
    }
}

extension DDError {
    public init(error: Error) {
        if isNSErrorOrItsSubclass(error) {
            let nsError = error as NSError
            self.type = "\(nsError.domain) - \(nsError.code)"
            if nsError.userInfo[NSLocalizedDescriptionKey] != nil {
                self.message = nsError.localizedDescription
            } else {
                self.message = nsError.description
            }
            self.stack = "\(nsError)"
        } else {
            let swiftError = error
            self.type = "\(Swift.type(of: swiftError))"
            self.message = "\(swiftError)"
            self.stack = "\(swiftError)"
        }

        self.sourceType = "ios"
    }
}

private func isNSErrorOrItsSubclass(_ error: Error) -> Bool {
    var mirror: Mirror? = Mirror(reflecting: error)

    while mirror != nil {
        if mirror?.subjectType == NSError.self {
            return true
        }
        mirror = mirror?.superclassMirror
    }
    return false
}

/// An exception thrown due to programmer error when calling SDK public API.
/// It makes the SDK non-functional and print the error to developer in debugger console..
/// When thrown, check if configuration passed to `Datadog.initialize(...)` is correct
/// and if you do not call any other SDK methods before it returns.
public struct ProgrammerError: Error, CustomStringConvertible {
    public let description: String
    public init(description: String) {
        self.description = "🔥 Datadog SDK usage error: \(description)"
    }
}

/// An exception thrown internally by SDK.
/// It is always handled by SDK (keeps it functional) and never passed to the user until `Datadog.verbosity` is set (then it might be printed in debugger console).
/// `InternalError` might be thrown due to programmer error (API misuse) or SDK internal inconsistency or external issues (e.g.  I/O errors). The SDK
/// should always recover from that failures.
public struct InternalError: Error, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

public struct ObjcException: Error {
    /// A closure to catch Objective-C runtime exception and rethrow as `Swift.Error`.
    ///
    /// - Important: Does nothing by default, it must be set to an Objective-C interopable function.
    ///
    /// - Warning: As stated in [Objective-C Automatic Reference Counting (ARC)](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions),
    /// in Objective-C, ARC is not exception-safe and  does not perform releases which would occur at the end of a
    /// full-expression if that full-expression throws an exception. Therefore, ARC-generated code leaks by default
    /// on exceptions.
    public static var rethrow: ((() -> Void) throws -> Void) = { $0() }

    /// The underlying `NSError` describing the `NSException`
    /// thrown by Objective-C runtime.
    public let error: Error
    /// The source file in which the exception was raised.
    public let file: String
    /// The line number on which the exception was raised.
    public let line: Int
}

/// Rethrow Objective-C runtime exception as `Swift.Error`.
///
/// - Warning: As stated in [Objective-C Automatic Reference Counting (ARC)](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions),
/// in Objective-C, ARC is not exception-safe and  does not perform releases which would occur at the end of a
/// full-expression if that full-expression throws an exception. Therefore, ARC-generated code leaks by default
/// on exceptions.
/// - throws: `ObjcException` if an exception was raised by the Objective-C runtime.
@discardableResult
public func objc_rethrow<T>(_ block: () throws -> T, file: String = #fileID, line: Int = #line) throws -> T {
    var value: T! //swiftlint:disable:this implicitly_unwrapped_optional
    var swiftError: Error?
    do {
        try ObjcException.rethrow {
            do {
                value = try block()
            } catch {
                swiftError = error
            }
        }
    } catch {
        // wrap the underlying objc runtime exception in
        // a `ObjcException` for easier matching during
        // escalation.
        throw ObjcException(error: error, file: file, line: line)
    }

    return try swiftError.map { throw $0 } ?? value
}
