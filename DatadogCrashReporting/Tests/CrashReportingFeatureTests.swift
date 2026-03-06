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
        let expectation = self.expectation(description: "plugin received initial crash context")
        plugin.didInjectContext = { expectation.fulfill() }

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

        withExtendedLifetime(feature) {
            waitForExpectations(timeout: 0.5)

            // Then
            XCTAssertNotNil(plugin.injectedContextData)
            XCTAssertNotNil(contextProvider.onCrashContextChange)
            let decodedContext = try? CrashReportingFeature.crashContextDecoder.decode(
                CrashContext.self,
                from: plugin.injectedContextData!
            )
            XCTAssertEqual(decodedContext?.service, "test-service")
            XCTAssertEqual(decodedContext?.env, "test-env")
        }
    }

    // MARK: - Crash Report Reading Tests

    func testItSendsLaunchReportWhenNoPendingCrash() async {
        // Given
        let plugin = CrashReportingPluginMock()
        plugin.pendingCrashReport = nil
        let sender = CrashReportSenderMock()

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin
        )

        // When
        await feature.sendCrashReportIfFound().value

        // Then
        XCTAssertNil(sender.sentCrashReport)
        XCTAssertNil(sender.sentCrashContext)
        XCTAssertEqual(sender.sentLaunchReport?.didCrash, false)
        XCTAssertNil(plugin.hasPurgedCrashReport)
    }

    func testItSendsCrashReportWithValidContext() async throws {
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

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin
        )

        // When
        await feature.sendCrashReportIfFound().value

        // Then
        XCTAssertNotNil(sender.sentCrashReport)
        XCTAssertNotNil(sender.sentCrashContext)
        XCTAssertEqual(sender.sentCrashContext?.service, "test-service")
        XCTAssertEqual(sender.sentCrashContext?.env, "test-env")
        XCTAssertEqual(sender.sentCrashContext?.version, "1.0.0")
        XCTAssertEqual(plugin.hasPurgedCrashReport, true)
    }

    func testItPurgesCrashReportWithMalformedContext() async {
        // Given
        let plugin = CrashReportingPluginMock()
        let malformedData = "not a valid context".data(using: .utf8)!
        let crashReport: DDCrashReport = .mockWith(context: malformedData)
        plugin.pendingCrashReport = crashReport

        let sender = CrashReportSenderMock()

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin
        )

        // When
        await feature.sendCrashReportIfFound().value

        // Then
        XCTAssertNil(sender.sentCrashReport)
        XCTAssertNil(sender.sentCrashContext)
        XCTAssertEqual(plugin.hasPurgedCrashReport, true)
    }

    // MARK: - Crash Context Injection Tests

    func testItInjectsCrashContextWhenContextChanges() {
        // Given
        let plugin = CrashReportingPluginMock()
        let expectation = self.expectation(description: "plugin received updated crash context")
        plugin.didInjectContext = { expectation.fulfill() }

        let sender = CrashReportSenderMock()
        let contextProvider = CrashContextProviderMock(initialCrashContext: nil)

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

        withExtendedLifetime(feature) {
            waitForExpectations(timeout: 0.5)

            // Then
            XCTAssertNotNil(plugin.injectedContextData)
            let decodedContext = try? CrashReportingFeature.crashContextDecoder.decode(
                CrashContext.self,
                from: plugin.injectedContextData!
            )
            XCTAssertEqual(decodedContext?.service, "new-service")
            XCTAssertEqual(decodedContext?.env, "new-env")
        }
    }

    // MARK: - Telemetry Tests

    func testItReportsTelemetryOnDecodingError() async {
        // Given
        let plugin = CrashReportingPluginMock()
        let malformedData = "not valid JSON".data(using: .utf8)!
        let crashReport: DDCrashReport = .mockWith(context: malformedData)
        plugin.pendingCrashReport = crashReport

        let sender = CrashReportSenderMock()
        let telemetry = TelemetryMock()

        let feature = CrashReportingFeature.mockWith(
            integration: sender,
            crashReportingPlugin: plugin,
            telemetry: telemetry
        )

        // When
        await feature.sendCrashReportIfFound().value

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)
        XCTAssertTrue(telemetry.messages.firstError()?.message.contains("Failed to decode crash report context") == true)
    }
}
