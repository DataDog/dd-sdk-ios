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
            context: .mockWith(
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
                dateCorrector: DateCorrectorMock()
            )
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
            environment: .mockRandom(),
            sdkVersion: .mockRandom()
        )
        let dateCorrectionOffset: TimeInterval = .mockRandom()

        // Given
        let crashReport: DDCrashReport = .mockWith(
            date: .mockDecember15th2019At10AMUTC(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            threads: [
                .init(name: "Thread 0", stack: "thread 0 stack", crashed: true, state: nil),
                .init(name: "Thread 1", stack: "thread 1 stack", crashed: false, state: nil),
                .init(name: "Thread 2", stack: "thread 2 stack", crashed: false, state: nil),
            ],
            binaryImages: [
                .init(libraryName: "library1", uuid: "uuid1", architecture: "arch", isSystemLibrary: true, loadAddress: "0xLoad1", maxAddress: "0xMax1"),
                .init(libraryName: "library2", uuid: "uuid2", architecture: "arch", isSystemLibrary: true, loadAddress: "0xLoad2", maxAddress: "0xMax2"),
                .init(libraryName: "library3", uuid: "uuid3", architecture: "arch", isSystemLibrary: false, loadAddress: "0xLoad3", maxAddress: "0xMax3"),
            ],
            meta: .init(
                incidentIdentifier: "incident-identifier",
                processName: "process-name",
                parentProcess: "parent-process",
                path: "process/path",
                codeType: "arch",
                exceptionType: "EXCEPTION_TYPE",
                exceptionCodes: "EXCEPTION_CODES"
            ),
            wasTruncated: false
        )
        let crashContext: CrashContext = .mockWith(
            lastUserInfo: Bool.random() ? .mockRandom() : .empty,
            lastRUMViewEvent: .mockRandom(),
            lastNetworkConnectionInfo: .mockRandom(),
            lastCarrierInfo: .mockRandom()
        )

        // When
        let integration = CrashReportingWithLoggingIntegration(
            logOutput: logOutput,
            context: .mockWith(
                service: configuration.serviceName,
                env: configuration.environment,
                version: configuration.applicationVersion,
                sdkVersion: configuration.sdkVersion,
                dateProvider: RelativeDateProvider(using: .mockRandomInThePast()),
                dateCorrector: DateCorrectorMock(offset: dateCorrectionOffset)
            )
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        let log = try XCTUnwrap(logOutput.recordedLog)
        let user = try XCTUnwrap(crashContext.lastUserInfo)

        let expectedLog = LogEvent(
            date: crashReport.date!.addingTimeInterval(dateCorrectionOffset),
            status: .emergency,
            message: crashReport.message,
            error: .init(
                kind: crashReport.type,
                message: crashReport.message,
                stack: crashReport.stack
            ),
            serviceName: configuration.serviceName,
            environment: configuration.environment,
            loggerName: CrashReportingWithLoggingIntegration.Constants.loggerName,
            loggerVersion: configuration.sdkVersion,
            threadName: nil,
            applicationVersion: configuration.applicationVersion,
            userInfo: .init(
                id: user.id,
                name: user.name,
                email: user.email,
                extraInfo: user.extraInfo
            ),
            networkConnectionInfo: crashContext.lastNetworkConnectionInfo,
            mobileCarrierInfo: crashContext.lastCarrierInfo,
            attributes: .init(
                userAttributes: [:],
                internalAttributes: [
                    DDError.threads: crashReport.threads,
                    DDError.binaryImages: crashReport.binaryImages,
                    DDError.meta: crashReport.meta,
                    DDError.wasTruncated: false
                ]
            ),
            tags: nil
        )

        XCTAssertEqual(expectedLog, log)
    }
}
