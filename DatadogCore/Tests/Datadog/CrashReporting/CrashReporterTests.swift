/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import DatadogLogs

@testable import DatadogCore
@testable import DatadogCrashReporting

class CrashReporterTests: XCTestCase {
    // MARK: - Sending Crash Report

    func testWhenPendingCrashReportIsFound_itIsSentAndPurged() throws {
        let expectation = self.expectation(description: "`CrashReportSender` sends the crash report")
        let crashContext: CrashContext = .mockRandom()
        let crashReport: DDCrashReport = .mockRandomWith(context: crashContext)
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport
        plugin.injectedContextData = crashContext.data

        // When
        let sender = CrashReportSenderMock()
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: sender,
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        // Then
        sender.didSendCrashReport = { expectation.fulfill() }
        feature.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        DDAssertReflectionEqual(sender.sentCrashReport, crashReport, "It should send the crash report retrieved from the `plugin`")
        let sentCrashContext = try XCTUnwrap(sender.sentCrashContext, "It should send the crash context")
        DDAssertDictionariesEqual(
            try sentCrashContext.data.toJSONObject(),
            try crashContext.data.toJSONObject(),
            "It should send the crash context retrieved from the `plugin`"
        )

        XCTAssertTrue(plugin.hasPurgedCrashReport == true, "It should ask to purge the crash report")
    }

    func testWhenPendingCrashReportIsFound_itIsSentMessageBus() throws {
        let expectation = self.expectation(description: "`CrashReportSender` sends the crash report to RUM feature")
        let crashContext: CrashContext = .mockRandom()
        let crashReport: DDCrashReport = .mockRandomWith(context: crashContext)
        let rumCrashReceiver = CrashReceiverMock()

        let core = PassthroughCoreMock(messageReceiver: rumCrashReceiver)

        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport
        plugin.injectedContextData = crashContext.data

        // When
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: MessageBusSender(core: core),
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        //Then
        plugin.didReadPendingCrashReport = { expectation.fulfill() }
        feature.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNotNil(rumCrashReceiver.receivedCrash, "crash must not be empty")
    }

    func testWhenPendingCrashReportIsNotFound_itDoesNothing() {
        let expectation = self.expectation(description: "`plugin` checks the crash report")
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = nil
        plugin.injectedContextData = nil

        // When
        let sender = CrashReportSenderMock()
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: sender,
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        // Then
        plugin.didReadPendingCrashReport = { expectation.fulfill() }
        feature.sendCrashReportIfFound()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(sender.sentCrashReport, "It should not send the crash report")
        XCTAssertNil(sender.sentCrashContext, "It should not send the crash context")
        XCTAssertTrue(plugin.hasPurgedCrashReport == false, "It should not purge the crash report")
    }

    func testWhenPendingCrashReportIsFoundButItHasUnavailableCrashContext_itPurgesTheCrashReportWithNoSending() {
        let expectation = self.expectation(description: "`CrashReportSender` does not send the crash report")
        expectation.isInverted = true
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = .mockWith(context: nil)
        plugin.injectedContextData = nil

        // When
        let sender = CrashReportSenderMock()
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: sender,
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        // Then
        sender.didSendCrashReport = { expectation.fulfill() }
        feature.sendCrashReportIfFound()

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
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(initialCrashContext: initialCrashContext),
            sender: CrashReportSenderMock(),
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        try withExtendedLifetime(feature) {
            // Then
            waitForExpectations(timeout: 0.5, handler: nil)
            DDAssertDictionariesEqual(
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
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: crashContextProvider,
            sender: CrashReportSenderMock(),
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        try withExtendedLifetime(feature) {
            // When
            let updatedCrashContext: CrashContext = .mockRandom()
            crashContextProvider.onCrashContextChange(updatedCrashContext)

            // Then
            waitForExpectations(timeout: 2, handler: nil)
            DDAssertDictionariesEqual(
                try plugin.injectedContextData!.toJSONObject(),
                try updatedCrashContext.data.toJSONObject()
            )
        }
    }

    func testGivenAnyCrashWithUnauthorizedTrackingConsent_whenSending_itIsDropped() throws {
        let expectation = self.expectation(description: "`plugin` checks the crash report")
        // Given
        let core = PassthroughCoreMock()
        let lastRUMViewEvent: RUMViewEvent? = Bool.random() ? .mockRandom() : nil

        let crashReport: DDCrashReport = .mockWith(
            date: .mockDecember15th2019At10AMUTC(),
            context: CrashContext.mockWith(
                trackingConsent: [.pending, .notGranted].randomElement()!,
                lastRUMViewEvent: lastRUMViewEvent // no matter if in RUM session or not
            ).data
        )

        let plugin = CrashReportingPluginMock()
        plugin.pendingCrashReport = crashReport
        plugin.didReadPendingCrashReport = { expectation.fulfill() }

        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: MessageBusSender(core: core),
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        // When
        feature.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(core.events.count, 0, "Crash must not be send as it doesn't have `.granted` consent")
    }

    // MARK: - Thread safety

    func testInjectingContextToPluginAreSynchronized() {
        let expectation = self.expectation(description: "`plugin` received at least 100 calls")
        expectation.expectedFulfillmentCount = 100
        expectation.assertForOverFulfill = false // to mitigate the call for initial context injection

        // State mutated by the mock plugin implementation - `DatadogCrashReporter` ensures its thread safety
        var mutableState: Bool = .random()

        let plugin = CrashReportingPluginMock()
        plugin.didInjectContext = {
            mutableState.toggle()
            expectation.fulfill()
        }

        let crashContextProvider = CrashContextProviderMock(initialCrashContext: .mockRandom())
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: crashContextProvider,
            sender: CrashReportSenderMock(),
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { crashContextProvider.onCrashContextChange(.mockRandom()) },
                { crashContextProvider.onCrashContextChange(.mockRandom()) }
            ],
            iterations: 50 // each closure is called 50 times
        )
        // swiftlint:enable opening_brace

        feature.flush()
        waitForExpectations(timeout: 0)
    }

    // MARK: - Usage

    func testGivenNoRegisteredCrashReportReceiver_whenPendingCrashReportIsFound_itPrintsWarning() {
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
        let feature = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(),
            sender: MessageBusSender(core: core),
            messageReceiver: NOPFeatureMessageReceiver(),
            telemetry: NOPTelemetry()
        )

        // When
        feature.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let logs = dd.logger.warnLogs

        XCTAssert(logs.contains(where: { $0.message == """
            In order to use Crash Reporting, RUM or Logging feature must be enabled.
            Make sure `RUM` or `Logs` are enabled when initializing Datadog SDK.
            """
        }))
    }
}
