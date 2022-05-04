/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2022 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMTelemetryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()

        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        Global.rum = RUMMonitor.initialize()
    }

    override func tearDown() {
        RUMFeature.instance?.deinitialize()
        Global.rum = DDNoopRUMMonitor()

        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - Sending Telemetry events

    func testSendTelemetryDebug() throws {
        // Given
        let configuredSource = String.mockAnySource()
        let telemetry: RUMTelemetry = .mockWith(
            source: configuredSource,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        telemetry.debug("Hello world!")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryDebugEvent.self).model(ofType: TelemetryDebugEvent.self) { event in
            XCTAssertEqual(event.date, 0)
            XCTAssertEqual(event.application?.id, telemetry.applicationID)
            XCTAssertEqual(event.version, telemetry.sdkVersion)
            XCTAssertEqual(event.service, "dd-sdk-ios")
            XCTAssertEqual(event.source, TelemetryDebugEvent.Source(rawValue: configuredSource))
            XCTAssertEqual(event.telemetry.message, "Hello world!")
        }
    }

    func testSendTelemetryError() throws {
        // Given
        let configuredSource = String.mockAnySource()
        let telemetry: RUMTelemetry = .mockWith(
            source: configuredSource,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        telemetry.error("Oops", kind: "OutOfMemory", stack: "a\nhay\nneedle\nstack")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryErrorEvent.self).model(ofType: TelemetryErrorEvent.self) { event in
            XCTAssertEqual(event.date, 0)
            XCTAssertEqual(event.application?.id, telemetry.applicationID)
            XCTAssertEqual(event.version, telemetry.sdkVersion)
            XCTAssertEqual(event.service, "dd-sdk-ios")
            XCTAssertEqual(event.source, TelemetryErrorEvent.Source(rawValue: configuredSource))
            XCTAssertEqual(event.telemetry.message, "Oops")
            XCTAssertEqual(event.telemetry.error?.kind, "OutOfMemory")
            XCTAssertEqual(event.telemetry.error?.stack, "a\nhay\nneedle\nstack")
        }
    }

    func testSendTelemetryDebug_withRUMContext() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny()

        // When
        Global.rum.startView(viewController: mockView)
        Global.rum.startUserAction(type: .scroll, name: .mockAny())
        telemetry.debug("telemetry debug")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 3)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryDebugEvent.self).model(ofType: TelemetryDebugEvent.self) { event in
            XCTAssertEqual(event.telemetry.message, "telemetry debug")
            XCTAssertValidRumUUID(event.action?.id)
            XCTAssertValidRumUUID(event.view?.id)
            XCTAssertValidRumUUID(event.session?.id)
        }
    }

    func testSendTelemetryError_withRUMContext() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny()

        // When
        Global.rum.startView(viewController: mockView)
        Global.rum.startUserAction(type: .scroll, name: .mockAny())
        telemetry.error("telemetry error")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 3)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryErrorEvent.self).model(ofType: TelemetryErrorEvent.self) { event in
            XCTAssertEqual(event.telemetry.message, "telemetry error")
            XCTAssertValidRumUUID(event.action?.id)
            XCTAssertValidRumUUID(event.view?.id)
            XCTAssertValidRumUUID(event.session?.id)
        }
    }
}
