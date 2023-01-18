/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

import XCTest
@testable import Datadog

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
        XCTAssertEqual(dd.telemetry.debugs.count, 1)
        XCTAssertEqual(dd.telemetry.debugs.first, message)
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
        XCTAssertEqual(dd.telemetry.errors.count, 1)
        let error = dd.telemetry.errors.first
        XCTAssertEqual(error?.message, message)
        XCTAssertEqual(error?.kind, kind)
        XCTAssertEqual(error?.stack, stack)
    }
}
