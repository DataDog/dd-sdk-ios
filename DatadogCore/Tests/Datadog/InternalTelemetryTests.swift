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
    let telemetry = TelemetryMock()

    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(messageReceiver: telemetry)
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        CoreRegistry.unregisterDefault()
        core = nil
        super.tearDown()
    }

    func testProxyDebugCallsTelemetryDebug() {
        // Given
        let id: String = .mockAny()
        let message: String = .mockAny()

        // When
        Datadog._internal.telemetry.debug(id: id, message: message)

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)
        guard case .debug(let receivedId, let receivedMessage, _) = telemetry.messages.first else {
            return XCTFail("A debug should be send to `telemetry`.")
        }

        XCTAssertEqual(receivedId, id)
        XCTAssertEqual(receivedMessage, message)
    }

    func testProxyErrorCallsTelemetryError() {
        // Given
        let id: String = .mockAny()
        let message: String = .mockAny()
        let stack: String = .mockAny()
        let kind: String = .mockAny()

        // When
        Datadog._internal.telemetry.error(id: id, message: message, kind: kind, stack: stack)

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)

        guard case .error(let receivedId, let receivedMessage, let receivedKind, let receivedStack) = telemetry.messages.first else {
            return XCTFail("An error should be send to `telemetry`.")
        }

        XCTAssertEqual(receivedId, id)
        XCTAssertEqual(receivedMessage, message)
        XCTAssertEqual(receivedKind, kind)
        XCTAssertEqual(receivedStack, stack)
    }
}
