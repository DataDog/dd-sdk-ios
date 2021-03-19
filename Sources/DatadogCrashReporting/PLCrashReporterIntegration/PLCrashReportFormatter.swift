/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CrashReporter
import Datadog

/// A convenience interface of the`PLCrashReport` to enable its testability.
internal protocol PLCrashReportType {
    var timestamp: Date? { get }
    var signalName: String? { get }
    var signalCode: String? { get }
    var exceptionName: String? { get }
    var exceptionReason: String? { get }
    var formattedStackTrace: String? { get }
    var contextData: Data? { get }
}

extension PLCrashReport: PLCrashReportType {
    var timestamp: Date? { systemInfo?.timestamp }
    var signalName: String? { signalInfo?.name }
    var signalCode: String? { signalInfo?.code }
    var exceptionName: String? { hasExceptionInfo ? exceptionInfo?.exceptionName : nil }
    var exceptionReason: String? { hasExceptionInfo ? exceptionInfo?.exceptionReason : nil }
    var formattedStackTrace: String? { PLCrashReportTextFormatter.stringValue(for: self, with: PLCrashReportTextFormatiOS) }
    var contextData: Data? { customData }
}

/// Formats the `PLCrashReport` to Datadog format (`DDCrashReport`).
internal struct PLCrashReportFormatter {
    private let unknown = "<unknown>"
    private let unavailable = "<unavailable>"

    func ddCrashReport(from crashReport: PLCrashReportType) -> DDCrashReport {
        return DDCrashReport(
            date: crashReport.timestamp,
            type: readType(from: crashReport),
            message: readMessage(from: crashReport),
            stackTrace: readStackTrace(from: crashReport),
            context: crashReport.contextData
        )
    }

    // MARK: - Private

    private func readType(from crashReport: PLCrashReportType) -> String {
        return "\(crashReport.signalName ?? unknown) (\(crashReport.signalCode ?? unknown))"
    }

    private func readMessage(from crashReport: PLCrashReportType) -> String {
        if crashReport.exceptionName != nil || crashReport.exceptionReason != nil {
            // If the crash was caused by an uncaught exception
            let exceptionName = crashReport.exceptionName // e.g. `NSInvalidArgumentException`
            let exceptionReason = crashReport.exceptionReason // e.g. `-[NSObject objectForKey:]: unrecognized selector sent to instance 0x...`
            return "Terminating app due to uncaught exception '\(exceptionName ?? unknown)', reason: '\(exceptionReason ?? unknown)'."
        } else {
            // Use signal description available in OS
            guard let signalName = crashReport.signalName else { // e.g. SIGILL
                return unknown
            }

            let knownSignalNames = Mirror(reflecting: sys_signame)
                .children
                .compactMap { $0.value as? UnsafePointer<Int8> }
                .map { String(cString: $0).uppercased() } // [HUP, INT, QUIT, ILL, TRAP, ABRT, ...]

            let knownSignalDescriptions = Mirror(reflecting: sys_siglist)
                .children
                .compactMap { $0.value as? UnsafePointer<Int8> }
                .map { String(cString: $0) } // [Hangup, Interrupt, Quit, Illegal instruction, ...]

            if knownSignalNames.count == knownSignalDescriptions.count { // sanity check
                if let index = knownSignalNames.firstIndex(where: { signalName == "SIG\($0)" }) {
                    return knownSignalDescriptions[index]
                }
            }

            return unknown
        }
    }

    private func readStackTrace(from crashReport: PLCrashReportType) -> String {
        return crashReport.formattedStackTrace ?? unavailable
    }
}
