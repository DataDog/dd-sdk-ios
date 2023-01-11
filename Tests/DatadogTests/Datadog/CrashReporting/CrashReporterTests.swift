/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class CrashReporterTests: XCTestCase {
    // MARK: - Sending Crash Report

    func testWhenPendingCrashReportIsFound_itIsSentAndPurged() throws {
        let expectation = self.expectation(description: "`LoggingOrRUMsender` sends the crash report")
        let crashContext: CrashContext = .mockRandom()
        let crashReport: DDCrashReport = .mockRandomWith(context: crashContext)
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport
        plugin.injectedContextData = crashContext.data

        // When
        let sender = CrashReportSenderMock()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: sender,
            messageReceiver: NOPFeatureMessageReceiver()
        )

        // Then
        sender.didSendCrashReport = { expectation.fulfill() }
        crashReporter.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(sender.sentCrashReport, crashReport, "It should send the crash report retrieved from the `plugin`")
        let sentCrashContext = try XCTUnwrap(sender.sentCrashContext, "It should send the crash context")
        AssertDictionariesEqual(
            try sentCrashContext.data.toJSONObject(),
            try crashContext.data.toJSONObject(),
            "It should send the crash context retrieved from the `plugin`"
        )

        XCTAssertTrue(plugin.hasPurgedCrashReport == true, "It should ask to purge the crash report")
    }

    func testWhenPendingCrashReportIsNotFound_itDoesNothing() {
        let expectation = self.expectation(description: "`plugin` checks the crash report")
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = nil
        plugin.injectedContextData = nil

        // When
        let sender = CrashReportSenderMock()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: sender,
            messageReceiver: NOPFeatureMessageReceiver()
        )

        // Then
        plugin.didReadPendingCrashReport = { expectation.fulfill() }
        crashReporter.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(sender.sentCrashReport, "It should not send the crash report")
        XCTAssertNil(sender.sentCrashContext, "It should not send the crash context")
        XCTAssertTrue(plugin.hasPurgedCrashReport == false, "It should not purge the crash report")
    }

    func testWhenPendingCrashReportIsFoundButItHasUnavailableCrashContext_itPurgesTheCrashReportWithNoSending() {
        let expectation = self.expectation(description: "`LoggingOrRUMsender` does not send the crash report")
        expectation.isInverted = true
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = .mockWith(context: nil)
        plugin.injectedContextData = nil

        // When
        let sender = CrashReportSenderMock()
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: sender,
            messageReceiver: NOPFeatureMessageReceiver()
        )

        // Then
        sender.didSendCrashReport = { expectation.fulfill() }
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
            sender: CrashReportSenderMock(),
            messageReceiver: NOPFeatureMessageReceiver()
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
            sender: CrashReportSenderMock(),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        try withExtendedLifetime(crashReporter) {
            // When
            let updatedCrashContext: CrashContext = .mockRandom()
            crashContextProvider.onCrashContextChange(updatedCrashContext)

            // Then
            waitForExpectations(timeout: 2, handler: nil)
            AssertDictionariesEqual(
                try plugin.injectedContextData!.toJSONObject(),
                try updatedCrashContext.data.toJSONObject()
            )
        }
    }

    func testGivenAnyCrashWithUnauthorizedTrackingConsent_whenSending_itIsDropped() throws {
        let expectation = self.expectation(description: "`plugin` checks the crash report")
        // Given
        let core = PassthroughCoreMock()

        let crashReport: DDCrashReport = .mockWith(
            date: .mockDecember15th2019At10AMUTC(),
            context: CrashContext.mockWith(
                trackingConsent: [.pending, .notGranted].randomElement()!,
                lastRUMViewEvent: Bool.random() ? .mockRandom() : nil // no matter if in RUM session or not
            ).data
        )

        let plugin = CrashReportingPluginMock()
        plugin.pendingCrashReport = crashReport
        plugin.didReadPendingCrashReport = { expectation.fulfill() }

        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: MessageBusSender(core: core),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        // When
        crashReporter.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(core.events.count, 0, "Crash must not be send as it doesn't have `.granted` consent")
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
            sender: CrashReportSenderMock(),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { crashContextProvider.onCrashContextChange(.mockRandom()) },
                { crashReporter.sendCrashReportIfFound() }
            ],
            iterations: 50 // each closure is called 50 times
        )
        // swiftlint:enable opening_brace

        waitForExpectations(timeout: 2, handler: nil)
    }

    // MARK: - Usage

    func testGivenNoRegisteredCrashReportReceiver_whenPendingCrashReportIsFound_itPrintsError() {
        let expectation = self.expectation(description: "`plugin` checks the crash report")

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock()
        let plugin = CrashReportingPluginMock()
        plugin.pendingCrashReport = .mockWith(
            context: CrashContext.mockAny().data
        )

        plugin.didReadPendingCrashReport = { expectation.fulfill() }

        // When
        let crashReporter = CrashReporter(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: MessageBusSender(core: core),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        // When
        crashReporter.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            In order to use Crash Reporting, RUM or Logging feature must be enabled.
            Make sure `.enableRUM(true)` or `.enableLogging(true)` are configured
            when initializing Datadog SDK.
            """
        )
    }
}
