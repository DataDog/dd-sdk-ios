/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCrashReporting

class CrashReportSenderTests: XCTestCase {
    // MARK: - Sending Crash Reports Tests

    func testItSendsCrashReportWhenTrackingConsentIsGranted() {
        // Given
        let receiver = CrashReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)
        let sender = MessageBusSender(core: core)
        let crashContext: CrashContext = .mockWith(trackingConsent: .granted)
        let crashReport: DDCrashReport = .mockAny()

        // When
        sender.send(report: crashReport, with: crashContext)

        // Then
        XCTAssertNotNil(receiver.receivedCrash)
        XCTAssertEqual(receiver.receivedCrash?.report.type, crashReport.type)
        XCTAssertEqual(receiver.receivedCrash?.context.trackingConsent, .granted)
    }

    func testItDoesNotSendCrashReportWhenTrackingConsentIsNotGranted() {
        // Given
        let receiver = CrashReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)
        let sender = MessageBusSender(core: core)
        let crashContext: CrashContext = .mockWith(trackingConsent: .notGranted)
        let crashReport: DDCrashReport = .mockAny()

        // When
        sender.send(report: crashReport, with: crashContext)

        // Then
        XCTAssertNil(receiver.receivedCrash)
    }

    func testItDoesNotSendCrashReportWhenTrackingConsentIsPending() {
        // Given
        let receiver = CrashReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)
        let sender = MessageBusSender(core: core)
        let crashContext: CrashContext = .mockWith(trackingConsent: .pending)
        let crashReport: DDCrashReport = .mockAny()

        // When
        sender.send(report: crashReport, with: crashContext)

        // Then
        XCTAssertNil(receiver.receivedCrash)
    }

    func testItSendsCrashReportWithCorrectContext() {
        // Given
        let receiver = CrashReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)
        let sender = MessageBusSender(core: core)
        let crashContext: CrashContext = .mockWith(
            service: "test-service",
            env: "test-env",
            version: "1.0.0",
            trackingConsent: .granted
        )
        let crashReport: DDCrashReport = .mockAny()

        // When
        sender.send(report: crashReport, with: crashContext)

        // Then
        XCTAssertNotNil(receiver.receivedCrash)
        XCTAssertEqual(receiver.receivedCrash?.context.service, "test-service")
        XCTAssertEqual(receiver.receivedCrash?.context.env, "test-env")
        XCTAssertEqual(receiver.receivedCrash?.context.version, "1.0.0")
    }

    // MARK: - Sending Launch Reports Tests

    func testItSendsLaunchReport() {
        // Given
        let core = PassthroughCoreMock()
        let sender = MessageBusSender(core: core)
        let didCrash: Bool = .random()
        let launchReport: LaunchReport = .init(didCrash: didCrash)

        // When
        sender.send(launch: launchReport)

        // Then
        let receivedLaunchReport = core.context.additionalContext(ofType: LaunchReport.self)
        XCTAssertNotNil(receivedLaunchReport)
        XCTAssertEqual(receivedLaunchReport?.didCrash, didCrash)
    }
}
