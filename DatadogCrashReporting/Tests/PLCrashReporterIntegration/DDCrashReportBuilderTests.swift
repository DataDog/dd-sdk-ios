/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import CrashReporter

@testable import DatadogCrashReporting

class DDCrashReportBuilderTests: XCTestCase {
    func testItBuildsDDCrashReportFromPLCrashReport() throws {
        // Given
        let plCrashReport = try generateLiveReport() // live report of the current process

        // When
        let builder = DDCrashReportBuilder()
        let ddCrashReport = try builder.createDDCrashReport(from: plCrashReport)

        // Then
        XCTAssertGreaterThan(ddCrashReport.threads.count, 0, "Some thread(s) should be recorded")
        XCTAssertGreaterThan(ddCrashReport.binaryImages.count, 0, "Some binary image(s) should be recorded")

        // Because `plCrashReport` is generated for current process (it changes dynamically between
        // test runs) we cannot assert exact values in exported `DDCrashReport`. Instead, we assert
        // some of its properties:
        XCTAssertEqual(
            plCrashReport.threads?.count,
            ddCrashReport.threads.count,
            "`DDCrashReport` should include the same number of threads as `PLCrashReport`"
        )
        XCTAssertTrue(
            ddCrashReport.stack.contains("DatadogCrashReportingTests"),
            "`DDCrashReport's` stack should include at least one frame from `DatadogCrashReportingTests` image"
        )
        XCTAssertTrue(
            ddCrashReport.stack.contains("XCTest"),
            "`DDCrashReport's` stack should include at least one frame from `XCTest` image"
        )
        XCTAssertTrue(
            ddCrashReport.binaryImages.contains(where: { $0.libraryName == "DatadogCrashReportingTests" }),
            "`DDCrashReport` should include the image for `DatadogCrashReportingTests`"
        )
        XCTAssertTrue(
            // Assert on prefix as it's `XCTestCore` on iOS 15+ and `XCTest` earlier:
            ddCrashReport.binaryImages.contains(where: { $0.libraryName.hasPrefix("XCTest") }),
            "`DDCrashReport` should include the image for `XCTest`"
        )
    }

    // MARK: - Helper

    /// This method generates "live report" using `PLCrashReporter`.
    /// When calling `generateLiveReportAndReturnError()`, PLCR generates `PLCrashReport` object describing
    /// the running process. It doesn't issue any crash - just records running threads and binary images.
    private func generateLiveReport() throws -> PLCrashReport {
        let configuration = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [])
        let crashReporter = try XCTUnwrap(PLCrashReporter(configuration: configuration))
        try crashReporter.enableAndReturnError()

        let liveReportData = try crashReporter.generateLiveReportAndReturnError()
        let liveReport = try PLCrashReport(data: liveReportData)
        return liveReport
    }
}
