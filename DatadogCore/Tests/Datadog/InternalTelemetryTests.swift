/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class InternalTelemetryTests: XCTestCase {
    func testProxyDebugCallsTelemetryDebug() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        let id: String = .mockAny()
        let message: String = .mockAny()

        // When
        Datadog._internal.telemetry.debug(id: id, message: message)

        // Then
        XCTAssertEqual(dd.telemetry.messages.count, 1)
        guard case .debug(let receivedId, let receivedMessage, _) = dd.telemetry.messages.first else {
            return XCTFail("A debug should be send to `DD.telemetry`.")
        }

        XCTAssertEqual(receivedId, id)
        XCTAssertEqual(receivedMessage, message)
    }

    func testProxyErrorCallsTelemetryError() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        let id: String = .mockAny()
        let message: String = .mockAny()
        let stack: String = .mockAny()
        let kind: String = .mockAny()

        // When
        Datadog._internal.telemetry.error(id: id, message: message, kind: kind, stack: stack)

        // Then
        XCTAssertEqual(dd.telemetry.messages.count, 1)

        guard case .error(let receivedId, let receivedMessage, let receivedKind, let receivedStack) = dd.telemetry.messages.first else {
            return XCTFail("An error should be send to `DD.telemetry`.")
        }

        XCTAssertEqual(receivedId, id)
        XCTAssertEqual(receivedMessage, message)
        XCTAssertEqual(receivedKind, kind)
        XCTAssertEqual(receivedStack, stack)
    }
}
