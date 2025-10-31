/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
#elseif swift(>=6.0)
internal import KSCrashRecording
#else
@_implementationOnly import KSCrashRecording
#endif
// swiftlint:enable duplicate_imports

/// A KSCrash filter that converts untyped crash reports into type-safe dictionaries.
///
/// This filter transforms KSCrash's raw string-keyed dictionaries (`[String: Any]`) into
/// `CrashDictionary` structures (`[CrashField: Any]`), which provide:
///
/// - **Type-safe keys**: String keys are converted to `CrashField` enum
/// - **Type-checked value access**: Convenient methods for extracting values\
///
/// ## Integration
///
/// This filter must be placed **first** in the KSCrash filter chain, before any other
/// Datadog filters, as subsequent filters (`DatadogDiagnosticFilter`, `DatadogCrashReportFilter`)
/// rely on `CrashDictionary`'s type-safe accessors.
internal final class DatadogTypeSafeFilter: NSObject, CrashReportFilter {
    /// Converts untyped crash reports into type-safe dictionaries with compile-time key validation.
    ///
    /// This method transforms each KSCrash report from its raw string-keyed format
    /// into a `CrashDictionary`, enabling:
    /// - Type-safe key access through `CrashField` enums
    /// - Value extraction with type checking
    /// - Prevention of runtime errors from typos and type mismatches
    ///
    /// The conversion is recursive, ensuring that all nested structures benefit from
    /// the same type safety guarantees.
    ///
    /// - Parameters:
    ///   - reports: The raw KSCrash reports to convert
    ///   - onCompletion: Completion handler called with type-safe reports. If conversion
    ///                   fails for any report (e.g., invalid structure), `nil` is returned
    ///                   along with the error.
    func filterReports(
        _ reports: [CrashReport],
        onCompletion: (([CrashReport]?, (Error)?) -> Void)?
    ) {
        do {
            let reports = try reports.map { report in
                // Validate and extract the raw report dictionary
                // KSCrash reports come as untyped dictionaries, we need to ensure it's valid
                guard let report = report as? CrashReportDictionary else {
                    throw CrashReportException(description: "KSCrash report untypedValue is not a dictionary")
                }

                // Convert to typed dictionary with type-safe key access
                // This recursively converts all nested dictionaries and arrays to use CrashField keys
                return AnyCrashReport(CrashFieldDictionary(from: report.value))
            }

            onCompletion?(reports, nil)
        } catch {
            onCompletion?(nil, error)
        }
    }
}
