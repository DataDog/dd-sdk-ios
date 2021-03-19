/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogCrashReporting
@testable import Datadog

class PLCrashReportFormatterTests: XCTestCase {
    private struct PLCrashReportMock: PLCrashReportType {
        var timestamp: Date? = nil
        var signalName: String? = nil
        var signalCode: String? = nil
        var exceptionName: String? = nil
        var exceptionReason: String? = nil
        var formattedStackTrace: String? = nil
        var contextData: Data? = nil
    }

    private let formatter = PLCrashReportFormatter()

    func testItReadsDateFromPLCrashReportTimestamp() {
        let crashReportWithTimestamp = PLCrashReportMock(timestamp: Date())
        let crashReportWithNoTimestamp = PLCrashReportMock(timestamp: nil)

        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReportWithTimestamp).date,
            crashReportWithTimestamp.timestamp
        )
        XCTAssertNil(
            formatter.ddCrashReport(from: crashReportWithNoTimestamp).date
        )
    }

    func testItReadsTypeFromPLCrashReportSignalInfo() {
        let crashReport1 = PLCrashReportMock(signalName: "SIGNAME", signalCode: "SIG_CODE")
        let crashReport2 = PLCrashReportMock(signalName: "SIGNAME", signalCode: nil)
        let crashReport3 = PLCrashReportMock(signalName: nil, signalCode: "SIG_CODE")
        let crashReport4 = PLCrashReportMock(signalName: nil, signalCode: nil)

        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport1).type,
            "SIGNAME (SIG_CODE)"
        )
        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport2).type,
            "SIGNAME (<unknown>)"
        )
        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport3).type,
            "<unknown> (SIG_CODE)"
        )
        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport4).type,
            "<unknown> (<unknown>)"
        )
    }

    func testWhenPLCrashReportHasExceptionInfo_thenItReadsMessageFromIt() {
        let crashReport1 = PLCrashReportMock(exceptionName: "ExceptionName", exceptionReason: "Exception reason")
        let crashReport2 = PLCrashReportMock(exceptionName: "ExceptionName", exceptionReason: nil)
        let crashReport3 = PLCrashReportMock(exceptionName: nil, exceptionReason: "Exception reason")

        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport1).message,
            "Terminating app due to uncaught exception 'ExceptionName', reason: 'Exception reason'."
        )
        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport2).message,
            "Terminating app due to uncaught exception 'ExceptionName', reason: '<unknown>'."
        )
        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport3).message,
            "Terminating app due to uncaught exception '<unknown>', reason: 'Exception reason'."
        )
    }

    func testWhenPLCrashReportHasNoExceptionInfo_thenItReadsMessageFromSignalInfo() {
        let signalDescriptionByName = [
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
            "UNKNOWN_SIGNAL_NAME": "<unknown>", // sanity check
        ]

        signalDescriptionByName.forEach { signalName, signalDescription in
            let crashReport = PLCrashReportMock(signalName: signalName)
            XCTAssertEqual(
                formatter.ddCrashReport(from: crashReport).message,
                signalDescription
            )
        }
    }

    func testWhenPLCrashReportHasNoExceptionInfoAndNoSignalInfo_thenMessageDefaultsToUknown() {
        let crashReport = PLCrashReportMock(
            signalName: nil,
            signalCode: nil,
            exceptionName: nil,
            exceptionReason: nil
        )

        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReport).message,
            "<unknown>"
        )
    }

    func testItReadsStackTraceFromPLCrashReportTimestamp() {
        let crashReportWithStackTrace = PLCrashReportMock(formattedStackTrace: "stack trace")
        let crashReportWithNoStackTrace = PLCrashReportMock(formattedStackTrace: nil)

        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReportWithStackTrace).stackTrace,
            crashReportWithStackTrace.formattedStackTrace
        )
        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReportWithNoStackTrace).stackTrace,
            "<unavailable>"
        )
    }

    func testItReadsContextDataFromPLCrashReportCustomData() {
        let crashReportWithCustomData = PLCrashReportMock(contextData: "some data".data(using: .utf8))
        let crashReportWithNoCustomData = PLCrashReportMock(contextData: nil)

        XCTAssertEqual(
            formatter.ddCrashReport(from: crashReportWithCustomData).context,
            crashReportWithCustomData.contextData
        )
        XCTAssertNil(
            formatter.ddCrashReport(from: crashReportWithNoCustomData).context
        )
    }
}
