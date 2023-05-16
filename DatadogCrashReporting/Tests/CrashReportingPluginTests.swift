/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCrashReporting

class CrashReportingPluginTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(PLCrashReporterPlugin.thirdPartyCrashReporter)
    }

    override func tearDown() {
        XCTAssertNil(PLCrashReporterPlugin.thirdPartyCrashReporter)
        super.tearDown()
    }

    // MARK: - Processing Crash Report in Caller

    func testGivenPendingCrashReport_whenCallerSucceedsWithItsProcessing_itIsPurged() throws {
        let expectation = self.expectation(description: "Crash Report was delivered to the caller.")
        let crashReporter = try ThirdPartyCrashReporterMock()
        let plugin = PLCrashReporterPlugin { crashReporter }
        defer { PLCrashReporterPlugin.thirdPartyCrashReporter = nil }

        // Given
        crashReporter.pendingCrashReport = .mockAny()

        // When
        plugin.readPendingCrashReport { crashReport in
            XCTAssertEqual(crashReport, crashReporter.pendingCrashReport)
            expectation.fulfill()
            return true // the caller succeeded in processing the crash report
        }

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(crashReporter.hasPurgedPendingCrashReport)
    }

    func testGivenPendingCrashReport_whenCallerSucceedsInItsProcessing_itIsPurged() throws {
        let expectation = self.expectation(description: "Crash Report was delivered to the caller.")
        let crashReporter = try ThirdPartyCrashReporterMock()
        let plugin = PLCrashReporterPlugin { crashReporter }
        defer { PLCrashReporterPlugin.thirdPartyCrashReporter = nil }

        // Given
        crashReporter.pendingCrashReport = .mockAny()

        // When
        plugin.readPendingCrashReport { crashReport in
            XCTAssertEqual(crashReport, crashReporter.pendingCrashReport)
            expectation.fulfill()
            return true
        }

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(crashReporter.hasPurgedPendingCrashReport)
    }

    func testGivenNoPendingCrashReport_whenCallerRequestIsMade_itReceivesNil() throws {
        let expectation = self.expectation(description: "No Crash Report was delivered to the caller.")
        let crashReporter = try ThirdPartyCrashReporterMock()
        let plugin = PLCrashReporterPlugin { crashReporter }
        defer { PLCrashReporterPlugin.thirdPartyCrashReporter = nil }

        // Given
        crashReporter.pendingCrashReport = nil

        // When
        plugin.readPendingCrashReport { crashReport in
            XCTAssertNil(crashReport)
            expectation.fulfill()
            return true
        }

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Injecting Crash Context

    func testItForwardsCrashContextToCrashReporter() throws {
        let crashReporter = try ThirdPartyCrashReporterMock()
        let plugin = PLCrashReporterPlugin { crashReporter }
        defer { PLCrashReporterPlugin.thirdPartyCrashReporter = nil }

        let context = "some context".data(using: .utf8)!
        plugin.inject(context: context)

        XCTAssertEqual(crashReporter.injectedContext, context)
    }

    // MARK: - Handling Errors

    func testGivenPendingCrashReport_whenItsLoadingFails_itPrintsError() throws {
        let expectation = self.expectation(description: "No Crash Report was delivered to the caller.")
        var errorPrinted: String?

        consolePrint = { errorPrinted = $0 }
        defer { consolePrint = { print($0) } }

        let crashReporter = try ThirdPartyCrashReporterMock()
        let plugin = PLCrashReporterPlugin { crashReporter }
        defer { PLCrashReporterPlugin.thirdPartyCrashReporter = nil }

        // Given
        crashReporter.pendingCrashReport = .mockAny()
        crashReporter.pendingCrashReportError = ErrorMock("Reading error")

        // When
        plugin.readPendingCrashReport { crashReport in
            XCTAssertNil(crashReport)
            expectation.fulfill()
            return .random()
        }

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertFalse(crashReporter.hasPurgedPendingCrashReport)
        XCTAssertEqual(
            errorPrinted,
            "🔥 DatadogCrashReporting error: failed to load crash report: Reading error"
        )
    }

    func testWhenCrashReporterCannotBeEnabled_itPrintsError() {
        var errorPrinted: String?

        consolePrint = { errorPrinted = $0 }
        defer { consolePrint = { print($0) } }

        // When
        ThirdPartyCrashReporterMock.initializationError = ErrorMock("Initialization error")
        defer { ThirdPartyCrashReporterMock.initializationError = nil }

        // Then
        _ = PLCrashReporterPlugin { try ThirdPartyCrashReporterMock() }

        XCTAssertEqual(
            errorPrinted,
            "🔥 DatadogCrashReporting error: failed to enable crash reporter: Initialization error"
        )
    }
}
