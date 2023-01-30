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

    public init(type: String, message: String, stack: String) {
        self.type = type
        self.message = message
        self.stack = stack
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
