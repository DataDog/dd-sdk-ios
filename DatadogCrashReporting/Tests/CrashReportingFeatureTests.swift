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

    func testItRecoversMalformedAttributesWhenInjectingCrashContext() throws {
        struct AlwaysFailingAttribute: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    self,
                    .init(codingPath: encoder.codingPath, debugDescription: "failure")
                )
            }
        }

        let plugin = CrashReportingPluginMock()
        let crashContext: CrashContext = .mockWith(
            userInfo: UserInfo(
                id: "user-id",
                extraInfo: [
                    "valid": "preserved",
                    "invalid": AlwaysFailingAttribute(),
                ]
            )
        )
        let feature = CrashReportingFeature.mockWith(
            integration: CrashReportSenderMock(),
            crashReportingPlugin: plugin,
            crashContextProvider: CrashContextProviderMock(initialCrashContext: crashContext)
        )

        feature.flush()

        let data = try XCTUnwrap(plugin.injectedContextData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let user = try XCTUnwrap(json["userInfo"] as? [String: Any])

        XCTAssertEqual(user["id"] as? String, "user-id")
        XCTAssertEqual(user["valid"] as? String, "preserved")
        XCTAssertTrue(user["invalid"] is NSNull)
    }

    // MARK: - Configuration Tests

    /// The setting as RUM resolves it, through `CrashReportingConfiguration` without importing
    /// `DatadogCrashReporting`. `nil` means Crash Reporting was never enabled, in which case backtrace generation is
    /// *unavailable* rather than *disabled* and App Hangs report it differently.
    ///
    /// Note: `FeatureRegistrationCoreMock` resolves by type and ignores the name, so these tests cannot catch a
    /// divergence between the registered and the looked-up name - `testFeatureNameMatchesTheSharedConstant()` and the
    /// real-core tests in `GeneratingBacktraceTests` cover that.
    private func appHangBacktraceEnabled(in core: DatadogCoreProtocol) -> Bool? {
        core.feature(named: Feature.crashReporting, type: CrashReportingConfiguration.self)?
            .appHangBacktraceEnabled
    }

    func testFeatureNameMatchesTheSharedConstant() {
        // `CrashReportingFeature` declares no `name` of its own - it comes from the `CrashReportingConfiguration`
        // extension. A local one that diverged from this constant would shadow it and silently break RUM's lookup,
        // which resolves by the constant.
        XCTAssertEqual(CrashReportingFeature.name, Feature.crashReporting)
    }

    func testByDefault_itRegistersBacktraceReporterWithAppHangBacktracesEnabled() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let plugin = CrashReportingPluginMock()
        plugin.injectedBacktraceReporter = BacktraceReporterMock()

        // When
        try CrashReporting.enableOrThrow(with: plugin, in: core)

        // Then
        XCTAssertNotNil(try core.backtraceReporter.generateBacktrace(), "Backtrace reporter must be registered")
        XCTAssertEqual(
            appHangBacktraceEnabled(in: core),
            true,
            "The default must be published as `true` by a registered Feature. Asserting the resolved `?? true` "
            + "fallback instead would also pass if nothing were registered at all"
        )
    }

    func testWhenAppHangBacktracesAreDisabled_itStillRegistersBacktraceReporter() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let plugin = CrashReportingPluginMock()
        plugin.injectedBacktraceReporter = BacktraceReporterMock()

        // When
        try CrashReporting.enableOrThrow(
            with: plugin,
            in: core,
            configuration: .init(appHangBacktraceEnabled: false)
        )

        // Then
        XCTAssertNotNil(
            try core.backtraceReporter.generateBacktrace(),
            "Other consumers of backtrace generation must keep working"
        )
        XCTAssertEqual(appHangBacktraceEnabled(in: core), false)
    }

    func testGivenPluginWithNoBacktraceReporter_whenAppHangBacktracesAreDisabled_itStillRecordsTheOptOut() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let plugin = CrashReportingPluginMock()
        plugin.injectedBacktraceReporter = nil

        // When
        try CrashReporting.enableOrThrow(
            with: plugin,
            in: core,
            configuration: .init(appHangBacktraceEnabled: false)
        )

        // Then
        XCTAssertEqual(
            appHangBacktraceEnabled(in: core),
            false,
            "Opting out must be recorded even when the plugin provides no backtrace reporter, so that App Hangs "
            + "report the stack trace as disabled rather than as Crash Reporting never having been enabled"
        )
        XCTAssertNil(
            try core.backtraceReporter.generateBacktrace(),
            "Backtrace generation stays unavailable when the plugin provides no reporter"
        )
    }

    func testGivenPluginWithNoBacktraceReporter_whenAppHangBacktracesAreDisabled_itStillAcceptsALaterReporter() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let plugin = CrashReportingPluginMock()
        plugin.injectedBacktraceReporter = nil
        try CrashReporting.enableOrThrow(
            with: plugin,
            in: core,
            configuration: .init(appHangBacktraceEnabled: false)
        )
        XCTAssertNil(try core.backtraceReporter.generateBacktrace())

        // When
        try core.register(backtraceReporter: BacktraceReporterMock())

        // Then
        XCTAssertNotNil(
            try core.backtraceReporter.generateBacktrace(),
            "Recording the opt-out must not block backtrace generation for the consumers this configuration "
            + "promises are unaffected - crash reports, binary images on logs and RUM view events, and the public "
            + "`backtraceReporter` API"
        )
        XCTAssertEqual(
            appHangBacktraceEnabled(in: core),
            false,
            "Registering a backtrace reporter must not disturb the opt-out - they live on separate Features"
        )
    }

    func testGivenBacktraceReporterAlreadyRegistered_whenAppHangBacktracesAreDisabled_itStillRecordsTheOptOut() throws {
        // Given (a backtrace reporter was registered before Crash Reporting was enabled)
        let core = FeatureRegistrationCoreMock()
        try core.register(backtraceReporter: BacktraceReporterMock())
        XCTAssertNil(appHangBacktraceEnabled(in: core), "Crash Reporting is not enabled yet")

        let plugin = CrashReportingPluginMock()
        plugin.injectedBacktraceReporter = BacktraceReporterMock()

        // When
        try CrashReporting.enableOrThrow(
            with: plugin,
            in: core,
            configuration: .init(appHangBacktraceEnabled: false)
        )

        // Then
        XCTAssertEqual(
            appHangBacktraceEnabled(in: core),
            false,
            "The opt-out lives on `CrashReportingFeature`, so an already-registered backtrace reporter cannot "
            + "swallow it - otherwise App Hangs keep collecting stack traces after the app asked them not to"
        )
    }

    func testWhenEnablingWithPluginThroughThePublicAPI_itForwardsTheConfiguration() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let plugin = CrashReportingPluginMock()
        plugin.injectedBacktraceReporter = BacktraceReporterMock()

        // When (through the public API, so that the overload's own argument forwarding is covered)
        CrashReporting.enable(with: plugin, configuration: .init(appHangBacktraceEnabled: false), in: core)

        // Then
        XCTAssertEqual(
            appHangBacktraceEnabled(in: core),
            false,
            "The public overload must forward its `configuration`, not a default-constructed one"
        )
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
