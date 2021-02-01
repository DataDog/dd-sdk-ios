/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class CrashReportingIntegrationMock: CrashReportingIntegration {
    var sentCrashReport: DDCrashReport?

    func send(crashReport: DDCrashReport) {
        sentCrashReport = crashReport
    }
}

class CrashReportingFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(CrashReportingFeature.instance)
    }

    override func tearDown() {
        XCTAssertNil(CrashReportingFeature.instance)
        super.tearDown()
    }

    // MARK: - Sending Crash Report

    func testGivenPendingCrashReport_whenOnlyLoggingIntegrationIsEnabled_itSendsCrashReportThroughIntegration() {
        let crashReport: DDCrashReport = .mockRandom()
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport

        // When
        let loggingIntegration = CrashReportingIntegrationMock()
        let feature = CrashReportingFeature(
            configuration: .mockWith(crashReportingPlugin: plugin),
            loggingIntegration: loggingIntegration,
            rumIntegration: nil
        )

        // Then
        feature.sendCrashReportIfFound()

        XCTAssertTrue(
            plugin.hasPurgedCrashReport == true,
            "It should ask to purge the crash report"
        )
        XCTAssertEqual(loggingIntegration.sentCrashReport, crashReport)
    }

    func testGivenPendingCrashReport_whenOnlyRUMIntegrationIsEnabled_itSendsCrashReportThroughIntegration() {
        let crashReport: DDCrashReport = .mockRandom()
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport

        // When
        let rumIntegration = CrashReportingIntegrationMock()
        let feature = CrashReportingFeature(
            configuration: .mockWith(crashReportingPlugin: plugin),
            loggingIntegration: nil,
            rumIntegration: rumIntegration
        )

        // Then
        feature.sendCrashReportIfFound()

        XCTAssertTrue(
            plugin.hasPurgedCrashReport == true,
            "It should ask to purge the crash report"
        )
        XCTAssertEqual(rumIntegration.sentCrashReport, crashReport)
    }

    func testGivenPendingCrashReport_whenBothLoggingAndRUMIntegrationsAreEnabled_itSendsCrashReportThroughRUMIntegration() {
        let crashReport: DDCrashReport = .mockRandom()
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport

        // When
        let loggingIntegration = CrashReportingIntegrationMock()
        let rumIntegration = CrashReportingIntegrationMock()
        let feature = CrashReportingFeature(
            configuration: .mockWith(crashReportingPlugin: plugin),
            loggingIntegration: loggingIntegration,
            rumIntegration: rumIntegration
        )

        // Then
        feature.sendCrashReportIfFound()

        XCTAssertTrue(
            plugin.hasPurgedCrashReport == true,
            "It should ask to purge the crash report"
        )
        XCTAssertNil(loggingIntegration.sentCrashReport)
        XCTAssertEqual(rumIntegration.sentCrashReport, crashReport)
    }

    func testGivenPendingCrashReport_whenLoggingAndRUMIntegrationsAreNotEnabled_itDoesNotPurgeTheCrashReport() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let crashReport: DDCrashReport = .mockRandom()
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = crashReport

        // When
        let feature = CrashReportingFeature(
            configuration: .mockWith(crashReportingPlugin: plugin),
            loggingIntegration: nil,
            rumIntegration: nil
        )

        // Then
        feature.sendCrashReportIfFound()

        XCTAssertTrue(
            plugin.hasPurgedCrashReport == false,
            "It should not ask to purge the crash report"
        )
        XCTAssertEqual(output.recordedLog?.level, .warn)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            Pending crash report was found, but it cannot be send as both Logging and RUM features
            are disabled. Make sure `.enableRUM(true)` or `.enableLogging(true)` are configured
            when initializind Datadog SDK.
            """
        )
    }

    func testGivenNoPendingCrashReport_whenBothLoggingAndRUMIntegrationsAreEnabled_itDoesNotAskToPurgeCrashReport() {
        let plugin = CrashReportingPluginMock()

        // Given
        plugin.pendingCrashReport = nil

        // When
        let feature = CrashReportingFeature(
            configuration: .mockWith(crashReportingPlugin: plugin),
            loggingIntegration: CrashReportingIntegrationMock(),
            rumIntegration: CrashReportingIntegrationMock()
        )

        // Then
        feature.sendCrashReportIfFound()

        XCTAssertTrue(
            plugin.hasPurgedCrashReport == false,
            "It should not ask to purge the crash report"
        )
    }
}
