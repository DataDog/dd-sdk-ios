/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CrashReporterTests: XCTestCase {
    // MARK: - Sending Crash Report

    func testGivenPendingCrashReport_whenLoggingOrRUMIntegrationIsEnabled_itSendsAndPurgesTheCrashReport() throws {
        let expectation = self.expectation(description: "`LoggingOrRUMIntegration` sends the crash report")
        let crashContext: CrashContext = .mockRandom()
        let crashReport: DDCrashReport = .mockRandomWith(context: crashContext)
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport
        plugin.injectedContextData = crashContext.data

        // When
        let integration = CrashReportingIntegrationMock()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            loggingOrRUMIntegration: integration
        )

        // Then
        integration.didSendCrashReport = { expectation.fulfill() }
        crashReporter.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(integration.sentCrashReport, crashReport, "It should send the crash report retrieved from the `plugin`")
        let sentCrashContext = try XCTUnwrap(integration.sentCrashContext, "It should send the crash context")
        AssertDictionariesEqual(
            try sentCrashContext.data.toJSONObject(),
            try crashContext.data.toJSONObject(),
            "It should send the crash context retrieved from the `plugin`"
        )

        XCTAssertTrue(plugin.hasPurgedCrashReport == true, "It should ask to purge the crash report")
    }

    func testGivenNoPendingCrashReport_whenLoggingOrRUMIntegrationIsEnabled_itDoesNotSendTheCrashReport() {
        let expectation = self.expectation(description: "`plugin` checks the crash report")
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = nil
        plugin.injectedContextData = nil

        // When
        let integration = CrashReportingIntegrationMock()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            loggingOrRUMIntegration: integration
        )

        // Then
        plugin.didReadPendingCrashReport = { expectation.fulfill() }
        crashReporter.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(integration.sentCrashReport, "It should not send the crash report")
        XCTAssertNil(integration.sentCrashContext, "It should not send the crash context")
        XCTAssertTrue(plugin.hasPurgedCrashReport == false, "It should not purge the crash report")
    }

    func testGivenPendingCrashReportWithUnavailableCrashContext_whenLoggingOrRUMIntegrationIsEnabled_itPurgesTheCrashReportWithNoSending() {
        let expectation = self.expectation(description: "`LoggingOrRUMIntegration` does not send the crash report")
        expectation.isInverted = true
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = .mockWith(context: nil)
        plugin.injectedContextData = nil

        // When
        let integration = CrashReportingIntegrationMock()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            loggingOrRUMIntegration: integration
        )

        // Then
        integration.didSendCrashReport = { expectation.fulfill() }
        crashReporter.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(
            plugin.hasPurgedCrashReport == true,
            "It should ask to purge the crash report as the crash context is unavailable"
        )
    }

    // MARK: - Crash Context Injection

    func testWhenInitialized_itInjectsInitialCrashContextToThePlugin() throws {
        let expectation = self.expectation(description: "`plugin` received initial crash context")
        let plugin = CrashReportingPluginMock()
        plugin.didInjectContext = { expectation.fulfill() }

        // When
        let initialCrashContext: CrashContext = .mockRandom()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(initialCrashContext: initialCrashContext),
            loggingOrRUMIntegration: CrashReportingIntegrationMock()
        )

        try withExtendedLifetime(crashReporter) {
            // Then
            waitForExpectations(timeout: 0.5, handler: nil)
            AssertDictionariesEqual(
                try plugin.injectedContextData!.toJSONObject(),
                try initialCrashContext.data.toJSONObject()
            )
        }
    }

    func testWhenCrashContextChanges_itInjectsNewCrashContextToThePlugin() throws {
        let expectation = self.expectation(description: "`plugin` received initial and updated crash contexts")
        expectation.expectedFulfillmentCount = 2
        let plugin = CrashReportingPluginMock()
        plugin.didInjectContext = { expectation.fulfill() }

        let crashContextProvider = CrashContextProviderMock(initialCrashContext: .mockRandom())
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: crashContextProvider,
            loggingOrRUMIntegration: CrashReportingIntegrationMock()
        )

        try withExtendedLifetime(crashReporter) {
            // When
            let updatedCrashContext: CrashContext = .mockRandom()
            crashContextProvider.onCrashContextChange?(updatedCrashContext)

            // Then
            waitForExpectations(timeout: 2, handler: nil)
            AssertDictionariesEqual(
                try plugin.injectedContextData!.toJSONObject(),
                try updatedCrashContext.data.toJSONObject()
            )
        }
    }

    // MARK: - Thread safety

    func testAllCallsToPluginAreSynchronized() {
        let expectation = self.expectation(description: "`plugin` received at least 100 calls")
        expectation.expectedFulfillmentCount = 100
        expectation.assertForOverFulfill = false // to mitigate the call for initial context injection

        // State mutated by the mock plugin implementation - `CrashReporter` ensures its thread safety
        var mutableState: Bool = .random()

        let plugin = CrashReportingPluginMock()
        plugin.didInjectContext = {
            mutableState.toggle()
            expectation.fulfill()
        }
        plugin.didReadPendingCrashReport = {
            mutableState.toggle()
            expectation.fulfill()
        }

        let crashContextProvider = CrashContextProviderMock(initialCrashContext: .mockRandom())
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: crashContextProvider,
            loggingOrRUMIntegration: CrashReportingIntegrationMock()
        )

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { crashContextProvider.onCrashContextChange?(.mockRandom()) },
                { crashReporter.sendCrashReportIfFound() }
            ],
            iterations: 50 // each closure is called 50 times
        )
        // swiftlint:enable opening_brace

        waitForExpectations(timeout: 2, handler: nil)
    }

    // MARK: - Usage

    func testGivenPendingCrashReport_whenLoggingOrRUMIntegrationCannotBeObtained_itCannotBeInstantiated() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = .mockAny()

        // When
        XCTAssertNil(LoggingFeature.instance)
        XCTAssertNil(RUMFeature.instance)
        let crashReporter = CrashReporter(crashReportingFeature: .mockNoOp())

        // Then
        XCTAssertNil(crashReporter)
        XCTAssertEqual(output.recordedLog?.status, .error)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            In order to use Crash Reporting, RUM or Logging feature must be enabled.
            Make sure `.enableRUM(true)` or `.enableLogging(true)` are configured
            when initializing Datadog SDK.
            """
        )
    }
}
