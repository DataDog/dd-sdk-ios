/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
internal typealias KSCrashReport = KSCrash.CrashReport
#elseif swift(>=6.0)
internal import KSCrashRecording
internal typealias KSCrashReport = KSCrashRecording.CrashReport
#else
@_implementationOnly import KSCrashRecording
internal typealias KSCrashReport = KSCrashRecording.CrashReport
#endif
// swiftlint:enable duplicate_imports

/// A generic wrapper that adapts any value to conform to KSCrash's `CrashReport` protocol.
///
/// This class serves as a type-erased container that allows arbitrary data to be treated
/// as a crash report within the KSCrash framework. It's particularly useful when working
/// with custom crash report formats or when converting between different crash report
/// representations.
///
/// ## Usage
///
/// ```swift
/// let customData = ["crash": "information"]
/// let report = AnyCrashReport(customData)
/// // report can now be used anywhere KSCrashRecording.CrashReport is expected
/// ```
internal final class AnyCrashReport: NSObject, KSCrashReport {
    /// The wrapped value, stored as an untyped optional.
    ///
    /// This property holds the original value passed to the initializer without any
    /// type conversion or validation. Consumers are responsible for casting this
    /// value to the appropriate type.
    let untypedValue: Any?

    /// Creates a crash report wrapper around any value.
    ///
    /// This initializer accepts any type of value and wraps it to conform to the
    /// `CrashReport` protocol. No validation or type checking is performed.
    ///
    /// - Parameter any: The value to wrap. Can be `nil`, a dictionary, a custom object,
    ///                  or any other type that needs to be treated as a crash report.
    required init(_ any: Any?) {
        self.untypedValue = any
    }
}
