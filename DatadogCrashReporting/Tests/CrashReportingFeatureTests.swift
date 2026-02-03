/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCrashReporting

class CrashReportingFeatureTests: XCTestCase {
    // MARK: - Initialization Tests

    func testItInjectsCrashContextOnInitialization() throws {
        // Given
        let plugin = CrashReportingPluginMock()
        let sender = CrashReportSenderMock()
        let initialContext: CrashContext = .mockWith(
            service: "test-service",
            env: "test-env"
        )
        let contextProvider = CrashContextProviderMock(initialCrashContext: initialContext)

        // When
        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin,
            crashContextProvider: contextProvider
        )

        // Wait for async injection
        feature.flush()

        // Then
        XCTAssertNotNil(plugin.injectedContextData)
        XCTAssertNotNil(contextProvider.onCrashContextChange)
        let decodedContext = try CrashReportingFeature.crashContextDecoder.decode(
            CrashContext.self,
            from: plugin.injectedContextData!
        )
        XCTAssertEqual(decodedContext.service, "test-service")
        XCTAssertEqual(decodedContext.env, "test-env")
    }

    // MARK: - Crash Report Reading Tests

    func testItSendsLaunchReportWhenNoPendingCrash() {
        // Given
        let plugin = CrashReportingPluginMock()
        plugin.pendingCrashReport = nil
        let sender = CrashReportSenderMock()
        let expectation = self.expectation(description: "didReadPendingCrashReport")

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin
        )

        plugin.didReadPendingCrashReport = {
            expectation.fulfill()
        }

        // When
        feature.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertNil(sender.sentCrashReport)
        XCTAssertNil(sender.sentCrashContext)
        XCTAssertEqual(plugin.hasPurgedCrashReport, false)
    }

    func testItSendsCrashReportWithValidContext() {
        // Given
        let plugin = CrashReportingPluginMock()
        let crashContext: CrashContext = .mockWith(
            service: "test-service",
            env: "test-env",
            version: "1.0.0"
        )
        let crashReport: DDCrashReport = .mockRandomWith(context: crashContext)
        plugin.pendingCrashReport = crashReport

        let sender = CrashReportSenderMock()
        let expectation = self.expectation(description: "didSendCrashReport")

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin
        )

        sender.didSendCrashReport = {
            expectation.fulfill()
        }

        // When
        feature.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertNotNil(sender.sentCrashReport)
        XCTAssertNotNil(sender.sentCrashContext)
        XCTAssertEqual(sender.sentCrashContext?.service, "test-service")
        XCTAssertEqual(sender.sentCrashContext?.env, "test-env")
        XCTAssertEqual(sender.sentCrashContext?.version, "1.0.0")
        XCTAssertEqual(plugin.hasPurgedCrashReport, true)
    }

    func testItPurgesCrashReportWithMalformedContext() {
        // Given
        let plugin = CrashReportingPluginMock()
        let malformedData = "not a valid context".data(using: .utf8)!
        let crashReport: DDCrashReport = .mockWith(context: malformedData)
        plugin.pendingCrashReport = crashReport

        let sender = CrashReportSenderMock()
        let expectation = self.expectation(description: "didReadPendingCrashReport")

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin
        )

        plugin.didReadPendingCrashReport = {
            expectation.fulfill()
        }

        // When
        feature.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertNil(sender.sentCrashReport)
        XCTAssertNil(sender.sentCrashContext)
        XCTAssertEqual(plugin.hasPurgedCrashReport, true)
    }

    // MARK: - Crash Context Injection Tests

    func testItInjectsCrashContextWhenContextChanges() {
        // Given
        let plugin = CrashReportingPluginMock()
        let sender = CrashReportSenderMock()
        let contextProvider = CrashContextProviderMock()

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin,
            crashContextProvider: contextProvider
        )

        // When
        let newContext: CrashContext = .mockWith(
            service: "new-service",
            env: "new-env"
        )
        contextProvider.onCrashContextChange(newContext)
        feature.flush()

        // Then
        XCTAssertNotNil(plugin.injectedContextData)
        let decodedContext = try? CrashReportingFeature.crashContextDecoder.decode(
            CrashContext.self,
            from: plugin.injectedContextData!
        )
        XCTAssertEqual(decodedContext?.service, "new-service")
        XCTAssertEqual(decodedContext?.env, "new-env")
    }

    // MARK: - Telemetry Tests

    func testItReportsTelemetryOnDecodingError() {
        // Given
        let plugin = CrashReportingPluginMock()
        let malformedData = "not valid JSON".data(using: .utf8)!
        let crashReport: DDCrashReport = .mockWith(context: malformedData)
        plugin.pendingCrashReport = crashReport

        let sender = CrashReportSenderMock()
        let telemetry = TelemetryMock()
        let expectation = self.expectation(description: "didReadPendingCrashReport")

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin,
            telemetry: telemetry
        )

        plugin.didReadPendingCrashReport = {
            expectation.fulfill()
        }

        // When
        feature.sendCrashReportIfFound()

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertTrue(telemetry.messages.firstError()?.message.contains("Failed to decode crash report context") == true)
    }
}
