/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import KSCrashRecording
@testable import DatadogCrashReporting

class DatadogTypeSafeFilterTests: XCTestCase {
     // MARK: - Success Cases

    func testFilterReports_ConvertsValidReportsToCrashFieldDictionary() throws {
        // Given
        let filter = DatadogTypeSafeFilter()
        let inputReport: KSCrashRecording.CrashReportDictionary = .report(withValue: [
            "crash": ["error": ["type": "signal"]],
            "name": "MyApp"
        ])
        var capturedReports: [KSCrashRecording.CrashReport]?
        var capturedError: Error? = NSError()

        // When
        filter.filterReports([inputReport]) { reports, error in
            capturedReports = reports
            capturedError = error
        }

        // Then
        XCTAssertNil(capturedError)
        XCTAssertEqual(capturedReports?.count, 1)

        let dict = try XCTUnwrap(capturedReports?.first?.untypedValue as? CrashFieldDictionary)
        try XCTAssertEqual(dict.value(forKey: .name), "MyApp")

        let crash: CrashFieldDictionary = try dict.value(forKey: .crash)
        let error: CrashFieldDictionary = try crash.value(forKey: .error)
        try XCTAssertEqual(error.value(forKey: .type), "signal")
    }

    func testFilterReports_HandlesMultipleReports() throws {
        // Given
        let filter = DatadogTypeSafeFilter()
        let report1: KSCrashRecording.CrashReportDictionary = .report(withValue: ["name": "Report1"])
        let report2: KSCrashRecording.CrashReportDictionary = .report(withValue: ["name": "Report2"])
        var capturedReports: [KSCrashRecording.CrashReport]?

        // When
        filter.filterReports([report1, report2]) { reports, error in
            capturedReports = reports
        }

        // Then
        XCTAssertEqual(capturedReports?.count, 2)

        let dict1 = try XCTUnwrap(capturedReports?.first?.untypedValue as? CrashFieldDictionary)
        try XCTAssertEqual(dict1.value(forKey: .name), "Report1")

        let dict2 = try XCTUnwrap(capturedReports?.last?.untypedValue as? CrashFieldDictionary)
        try XCTAssertEqual(dict2.value(forKey: .name), "Report2")
    }

    // MARK: - Error Cases

    func testFilterReports_ReturnsErrorForInvalidReportType() {
        // Given - Create a mock object that isn't CrashReportDictionary
        let filter = DatadogTypeSafeFilter()
        let invalidReport = InvalidCrashReport()
        var capturedReports: [KSCrashRecording.CrashReport]? = []
        var capturedError: Error?

        // When
        filter.filterReports([invalidReport]) { reports, error in
            capturedReports = reports
            capturedError = error
        }

        // Then
        XCTAssertNil(capturedReports)
        XCTAssertNotNil(capturedError)

        let exception = capturedError as? CrashReportException
        XCTAssertNotNil(exception)
        XCTAssertTrue(exception?.description.contains("not a dictionary") ?? false)
    }

    func testFilterReports_StopsProcessingOnFirstError() {
        // Given
        let filter = DatadogTypeSafeFilter()
        let validReport = AnyCrashReport(["name": "Valid"])
        let invalidReport = InvalidCrashReport()
        var capturedReports: [KSCrashRecording.CrashReport]? = []
        var capturedError: Error?

        // When
        filter.filterReports([validReport, invalidReport]) { reports, error in
            capturedReports = reports
            capturedError = error
        }

        // Then
        XCTAssertNil(capturedReports)
        XCTAssertNotNil(capturedError)
    }
}

// MARK: - Test Helpers

/// Mock invalid crash report for testing error cases
private class InvalidCrashReport: NSObject, KSCrashRecording.CrashReport {
    var untypedValue: Any? { return "not a dictionary" }
}
