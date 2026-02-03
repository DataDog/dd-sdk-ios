/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogSessionReplay

class SessionReplayTelemetryTests: XCTestCase {
    func testDeduplicatedMessage() {
        // Given
        let forwarder = TelemetryMock()
        let telemetry = SessionReplayTelemetry(telemetry: forwarder, queue: NoQueue())
        let errorMessage: TelemetryMessage = .error(id: "1", message: .mockRandom(), kind: .mockRandom(), stack: .mockRandom())
        let debugMessage: TelemetryMessage = .debug(id: "1", message: .mockRandom(), attributes: nil)

        // When
        telemetry.send(telemetry: errorMessage)
        telemetry.send(telemetry: debugMessage)

        // Then
        XCTAssertEqual(forwarder.messages.count, 1)
        let error = forwarder.messages.firstError()
        XCTAssertEqual(error?.message, errorMessage.asError?.message)
    }

    func testForwardMessages() {
        // Given
        let forwarder = TelemetryMock()
        let telemetry = SessionReplayTelemetry(telemetry: forwarder, queue: NoQueue())
        let metricMessage: TelemetryMessage = .metric(.init(name: "test", attributes: [:], sampleRate: 100))
        let usageMessage: TelemetryMessage = .usage(.init(event: .addError))

        // When
        telemetry.send(telemetry: metricMessage)
        telemetry.send(telemetry: usageMessage)

        // Then
        XCTAssertEqual(forwarder.messages.count, 2)
        XCTAssertNotNil(forwarder.messages.firstMetric(named: "test"))
        XCTAssertNotNil(forwarder.messages.firstUsage())
    }

    func testThreadSafety() {
        // Given
        let expectation = self.expectation(description: "`telemetry` received 100 calls")
        expectation.expectedFulfillmentCount = 100

        let forwarder = TelemetryMock()
        let telemetry = SessionReplayTelemetry(telemetry: forwarder, queue: BackgroundAsyncQueue(label: "test"))

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { telemetry.send(telemetry: .error(id: .mockRandom(), message: .mockRandom(), kind: .mockRandom(), stack: .mockRandom())); expectation.fulfill() },
                { telemetry.send(telemetry: .debug(id: .mockRandom(), message: .mockRandom(), attributes: nil)); expectation.fulfill() },
                { telemetry.send(telemetry: .debug(id: .mockRandom(), message: .mockRandom(), attributes: nil)); expectation.fulfill() },
                { telemetry.send(telemetry: .metric(.init(name: .mockRandom(), attributes: [:], sampleRate: 100))); expectation.fulfill() }
            ],
            iterations: 25
        )
        // swiftlint:enable opening_brace

        waitForExpectations(timeout: 2, handler: nil)
    }
}

#endif
