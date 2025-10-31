/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import KSCrashRecording
@testable import DatadogCrashReporting

class DatadogDiagnosticFilterTests: XCTestCase {
    func testDiagnose_AddsMessageForUncaughtException() throws {
        // Given
        let json = """
        {
            "error": {
                "nsexception": {
                    "name": "NSInvalidArgumentException"
                },
                "reason": "-[NSObject objectForKey:]: unrecognized selector sent to instance 0x600003d8c120"
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)
        let filter = DatadogDiagnosticFilter()

        // When
        let diagnosis = try filter.diagnose(crash: report)

        // Then
        XCTAssertEqual(
            diagnosis,
            "Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[NSObject objectForKey:]: unrecognized selector sent to instance 0x600003d8c120'."
        )
    }

    func testDiagnose_AddsMessageForSignalCrash() throws {
        // Given
        let json = """
        {
            "error": {
                "signal": {
                    "name": "SIGSEGV"
                }
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)
        let filter = DatadogDiagnosticFilter()

        // When
        let diagnosis = try filter.diagnose(crash: report)

        // Then
        XCTAssertEqual(diagnosis, "Application crash: SIGSEGV (Segmentation fault)")
    }

    func testDiagnose_HandlesUnknownCrashType() throws {
        // Given
        let json = """
        {
            "error": {}
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)
        let filter = DatadogDiagnosticFilter()

        // When
        let diagnosis = try filter.diagnose(crash: report)

        // Then
        XCTAssertEqual(diagnosis, "Application crash: <unknown>")
    }

    func testDiagnose_HandlesPartialExceptionData() throws {
        // Given
        let json = """
        {
            "error": {
                "nsexception": {}
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)
        let filter = DatadogDiagnosticFilter()

        // When
        let diagnosis = try filter.diagnose(crash: report)

        // Then
        XCTAssertEqual(
            diagnosis,
            "Terminating app due to uncaught exception '<unknown>', reason: '<unknown>'."
        )
    }

    func testFilterReports_InjectsDiagnosisIntoMainCrash() throws {
        // Given
        let json = """
        {
            "crash": {
                "error": {
                    "signal": {
                        "name": "SIGABRT"
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)
        let filter = DatadogDiagnosticFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([AnyCrashReport(report)]) { reports, error in
            XCTAssertNil(error)
            capturedReports = reports
        }

        // Then
        let processedDict = try XCTUnwrap(capturedReports?.first?.untypedValue as? CrashFieldDictionary)
        let diagnosis: String = try processedDict.value(forKey: .crash, .diagnosis)
        XCTAssertEqual(diagnosis, "Application crash: SIGABRT (Abort trap)")
    }

    func testFilterReports_InjectsDiagnosisIntoRecrashReport() throws {
        // Given
        let json = """
        {
            "crash": {
                "error": {
                    "signal": {
                        "name": "SIGBUS"
                    }
                }
            },
            "recrash_report": {
                "crash": {
                    "error": {
                        "nsexception": {
                            "name": "NSRangeException"
                        },
                        "reason": "Array index out of bounds"
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let report = CrashFieldDictionary(from: dict)
        let filter = DatadogDiagnosticFilter()
        var capturedReports: [CrashReport]?

        // When
        filter.filterReports([AnyCrashReport(report)]) { reports, error in
            XCTAssertNil(error)
            capturedReports = reports
        }

        // Then
        let processedDict = try XCTUnwrap(capturedReports?.first?.untypedValue as? CrashFieldDictionary)
        let mainDiagnosis: String = try processedDict.value(forKey: .crash, .diagnosis)
        let recrashDiagnosis: String = try processedDict.value(forKey: .recrashReport, .crash, .diagnosis)
        XCTAssertEqual(mainDiagnosis, "Application crash: SIGBUS (Bus error)")
        XCTAssertEqual(recrashDiagnosis, "Terminating app due to uncaught exception 'NSRangeException', reason: 'Array index out of bounds'.")
    }
}
