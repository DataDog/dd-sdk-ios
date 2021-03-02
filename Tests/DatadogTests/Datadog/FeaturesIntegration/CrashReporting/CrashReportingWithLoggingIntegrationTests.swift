/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CrashReportingWithLoggingIntegrationTests: XCTestCase {
    private let logOutput = LogOutputMock()

    // MARK: - Testing Conditional Uploads

    func testWhenCrashReportHasUnauthorizedTrackingConsent_itIsNotSent() {
        // Given
        let crashReport: DDCrashReport = .mockWith(date: .mockDecember15th2019At10AMUTC())
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: [.pending, .notGranted].randomElement()!
        )

        // When
        let integration = CrashReportingWithLoggingIntegration(
            logOutput: logOutput,
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            dateCorrector: DateCorrectorMock(),
            configuration: .mockAny()
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertNil(logOutput.recordedLog)
    }

    // MARK: - Testing Uploaded Data

    func testWhenSendingCrashReport_itIncludesAllErrorInformation() throws {
        let configuration: FeaturesConfiguration.Common = .mockWith(
            applicationVersion: .mockRandom(),
            serviceName: .mockRandom(),
            environment: .mockRandom()
        )
        let dateCorrectionOffset: TimeInterval = .mockRandom()

        // Given
        let crashReport: DDCrashReport = .mockWith(
            date: .mockDecember15th2019At10AMUTC(),
            type: .mockRandom(),
            message: .mockRandom(),
            stackTrace: .mockRandom()
        )
        let crashContext: CrashContext = .mockWith(
            lastUserInfo: Bool.random() ? .mockRandom() : .empty,
            lastRUMViewEvent: .mockRandomWith(model: RUMViewEvent.mockRandom()),
            lastNetworkConnectionInfo: .mockRandom(),
            lastCarrierInfo: .mockRandom()
        )

        // When
        let integration = CrashReportingWithLoggingIntegration(
            logOutput: logOutput,
            dateProvider: RelativeDateProvider(using: .mockRandomInThePast()),
            dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset),
            configuration: configuration
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        let log = try XCTUnwrap(logOutput.recordedLog)
        let expectedLog = Log(
            date: crashReport.date!.addingTimeInterval(dateCorrectionOffset),
            status: .emergency,
            message: crashReport.message,
            error: DDError(
                type: crashReport.type,
                message: crashReport.message,
                stack: crashReport.stackTrace
            ),
            serviceName: configuration.serviceName,
            environment: configuration.environment,
            loggerName: CrashReportingWithLoggingIntegration.Constants.loggerName,
            loggerVersion: sdkVersion,
            threadName: nil,
            applicationVersion: configuration.applicationVersion,
            userInfo: crashContext.lastUserInfo!,
            networkConnectionInfo: crashContext.lastNetworkConnectionInfo,
            mobileCarrierInfo: crashContext.lastCarrierInfo,
            attributes: .init(userAttributes: [:], internalAttributes: nil),
            tags: nil
        )

        XCTAssertEqual(expectedLog, log)
    }
}
