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

/// A KSCrash filter that generates human-readable diagnostic messages for crash reports.
///
/// This filter is modeled after KSCrash's `KSCrashReportFilterDoctor` and serves the same
/// purpose: analyzing crash reports and producing descriptive diagnostic messages that explain
/// the cause of the crash in plain language.
///
/// ## Crash Types Handled
///
/// 1. **Uncaught Exceptions**: Objective-C/Swift exceptions that weren't caught by the application
///    - Extracts exception name and reason
///    - Format: `"Terminating app due to uncaught exception 'ExceptionName', reason: 'detailed reason'."`
///
/// 2. **Signal-based Crashes**: Low-level crashes caused by Unix signals
///    - Maps signal names to human-readable descriptions (SIGSEGV → Segmentation fault, etc.)
///    - Format: `"Application crash: SIGSEGV (Segmentation fault)"`
///
/// ## Processing Flow
///
/// For each crash report:
/// 1. Validates the report structure
/// 2. Analyzes crash data to determine the crash type
/// 3. Generates an appropriate diagnostic message
/// 4. Injects the diagnosis into both the main crash and recrash reports (if present)
/// 5. Returns the updated report
///
/// ## Integration
///
/// This filter should be placed early in the KSCrash filter chain, before the
/// `DatadogCrashReportFilter`, to ensure diagnostic information is available for
/// subsequent processing and reporting.
internal final class DatadogDiagnosticFilter: NSObject, CrashReportFilter {
    /// Placeholder text used when crash information is unavailable.
    private let unknown = "<unknown>"

    /// Placeholder text used for optional fields that are not present.
    private let unavailable = "???"

    /// Mapping of Unix signal names to human-readable descriptions.
    ///
    /// This dictionary provides user-friendly descriptions for all standard POSIX signals,
    /// matching the behavior of KSCrash's diagnostic filter.
    private let knownSignalDescriptionByName = [
        "SIGSIGNAL 0": "Signal 0",
        "SIGHUP": "Hangup",
        "SIGINT": "Interrupt",
        "SIGQUIT": "Quit",
        "SIGILL": "Illegal instruction",
        "SIGTRAP": "Trace/BPT trap",
        "SIGABRT": "Abort trap",
        "SIGEMT": "EMT trap",
        "SIGFPE": "Floating point exception",
        "SIGKILL": "Killed",
        "SIGBUS": "Bus error",
        "SIGSEGV": "Segmentation fault",
        "SIGSYS": "Bad system call",
        "SIGPIPE": "Broken pipe",
        "SIGALRM": "Alarm clock",
        "SIGTERM": "Terminated",
        "SIGURG": "Urgent I/O condition",
        "SIGSTOP": "Suspended (signal)",
        "SIGTSTP": "Suspended",
        "SIGCONT": "Continued",
        "SIGCHLD": "Child exited",
        "SIGTTIN": "Stopped (tty input)",
        "SIGTTOU": "Stopped (tty output)",
        "SIGIO": "I/O possible",
        "SIGXCPU": "Cputime limit exceeded",
        "SIGXFSZ": "Filesize limit exceeded",
        "SIGVTALRM": "Virtual timer expired",
        "SIGPROF": "Profiling timer expired",
        "SIGWINCH": "Window size changes",
        "SIGINFO": "Information request",
        "SIGUSR1": "User defined signal 1",
        "SIGUSR2": "User defined signal 2",
    ]

    /// Processes crash reports by adding human-readable diagnostic messages.
    ///
    /// This method analyzes each crash report, generates a diagnostic message describing
    /// the crash cause, and injects it into the report. The diagnosis is added to both
    /// the main crash report and any recrash reports present.
    ///
    /// - Parameters:
    ///   - reports: The crash reports to process and enhance with diagnostic information
    ///   - onCompletion: Completion handler called with the processed reports. If diagnosis
    ///                   generation fails for any report, the original reports are returned
    ///                   along with the error.
    func filterReports(
        _ reports: [CrashReport],
        onCompletion: (([CrashReport]?, (Error)?) -> Void)?
    ) {
        do {
            let reports = try reports.map { report in
                // Validate and extract the type-safe report dictionary
                guard var dict = report.untypedValue as? CrashFieldDictionary else {
                    throw CrashReportException(description: "KSCrash report untypedValue is not a CrashDictionary")
                }

                if let crash: CrashFieldDictionary = try dict.valueIfPresent(forKey: .crash), let diagnosis = try diagnose(crash: crash) {
                    dict.setValue(forKey: .crash, .diagnosis, value: diagnosis)
                }

                if let crash: CrashFieldDictionary = try dict.valueIfPresent(forKey: .recrashReport, .crash), let diagnosis = try diagnose(crash: crash) {
                    dict.setValue(forKey: .recrashReport, .crash, .diagnosis, value: diagnosis)
                }

                return AnyCrashReport(dict)
            }

            onCompletion?(reports, nil)
        } catch {
            onCompletion?(reports, error)
        }
    }

    /// Analyzes a crash report and generates a human-readable diagnostic message.
    ///
    /// This method examines the crash data to determine the crash type and constructs
    /// an appropriate diagnostic message. It follows a prioritized analysis:
    ///
    /// 1. **Exception-based crashes**: Checks for uncaught NSException
    /// 2. **Signal-based crashes**: Checks for Unix signals with known descriptions
    /// 3. **Unknown crashes**: Returns a generic message for unrecognized crash types
    ///
    /// - Parameter dict: The crash report dictionary containing crash information
    /// - Returns: A diagnostic message describing the crash, or `nil` if no crash data is found
    /// - Throws: `CrashReportException` if the report structure is invalid
    ///
    /// ## Example Messages
    ///
    /// - Exception: `"Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'unrecognized selector'."`
    /// - Signal: `"Application crash: SIGSEGV (Segmentation fault)"`
    /// - Unknown: `"Application crash: <unknown>"`
    func diagnose(crash dict: CrashFieldDictionary) throws -> String? {
        // Check for uncaught exception
        if let exception: CrashFieldDictionary = try dict.valueIfPresent(forKey: .error, .nsException) {
            let name: String = try exception.valueIfPresent(forKey: .name) ?? unknown // e.g. `NSInvalidArgumentException`
            let reason = try dict.valueIfPresent(forKey: .error, .reason) ?? unknown // e.g. `-[NSObject objectForKey:]: unrecognized selector sent to instance 0x...`
            return "Terminating app due to uncaught exception '\(name)', reason: '\(reason)'."
        }

        // Check for signal-based crash with known description
        if
            let name: String = try dict.valueIfPresent(forKey: .error, .signal, .name),
            let description = knownSignalDescriptionByName[name] {
            return "Application crash: \(name) (\(description))"
        }

        // Fallback for unknown crash types
        return "Application crash: \(unknown)"
    }
}
