/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogCore
@testable import DatadogObjc

class DDInternalLoggerTests: XCTestCase {
    let telemetry = TelemetryReceiverMock()

    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(messageReceiver: telemetry)
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testObjcTelemetryDebugCallsTelemetryDebug() throws {
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        // Given
        let id: String = .mockAny()
        let message: String = .mockAny()

        // When
        DDInternalLogger.telemetryDebug(id: id, message: message)

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)
        let debug = try XCTUnwrap(telemetry.messages.first?.asDebug, "A debug should be send to `telemetry`.")
        XCTAssertEqual(debug.id, id)
        XCTAssertEqual(debug.message, message)
    }

    func testObjcTelemetryErrorCallsTelemetryError() throws {
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        // Given
        let id: String = .mockAny()
        let message: String = .mockAny()
        let stack: String = .mockAny()
        let kind: String = .mockAny()

        // When
        DDInternalLogger.telemetryError(id: id, message: message, kind: kind, stack: stack)

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)

        let error = try XCTUnwrap(telemetry.messages.first?.asError, "An error should be send to `telemetry`.")
        XCTAssertEqual(error.id, id)
        XCTAssertEqual(error.message, message)
        XCTAssertEqual(error.kind, kind)
        XCTAssertEqual(error.stack, stack)
    }

    func testWhenTelemetryIsSentThroughObjc_thenItForwardsToDDTelemetry() throws {
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        // When
        let randomDebugMessage: String = .mockRandom()
        let randomErrorMessage: String = .mockRandom()
        DDInternalLogger.telemetryDebug(id: .mockAny(), message: randomDebugMessage)
        DDInternalLogger.telemetryError(id: .mockAny(), message: randomErrorMessage, kind: .mockAny(), stack: .mockAny())

        // Then
        XCTAssertEqual(telemetry.messages.count, 2)

        let debug = try XCTUnwrap(telemetry.messages.first?.asDebug, "A debug should be send to `telemetry`.")
        XCTAssertEqual(debug.message, randomDebugMessage)

        let error = try XCTUnwrap(telemetry.messages.last?.asError, "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message, randomErrorMessage)
    }
}
