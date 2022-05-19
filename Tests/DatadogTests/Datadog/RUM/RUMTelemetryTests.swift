/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2022 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMTelemetryTests: XCTestCase {
    let core = DatadogCoreMock()

    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()

        let rum: RUMFeature = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        core.registerFeature(named: RUMFeature.featureName, instance: rum)
        Global.rum = RUMMonitor.initialize(in: core)
    }

    override func tearDown() {
        core.flush()
        Global.rum = DDNoopRUMMonitor()
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - Sending Telemetry events

    func testSendTelemetryDebug() throws {
        let telemetry: RUMTelemetry = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        telemetry.debug("Hello world!")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryDebugEvent.self).model(ofType: TelemetryDebugEvent.self) { event in
            XCTAssertEqual(event.date, 0)
            XCTAssertEqual(event.application?.id, telemetry.applicationID)
            XCTAssertEqual(event.version, telemetry.sdkVersion)
            XCTAssertEqual(event.service, "dd-sdk-ios")
            XCTAssertEqual(event.source, .ios)
            XCTAssertEqual(event.telemetry.message, "Hello world!")
        }
    }

    func testSendTelemetryError() throws {
        let telemetry: RUMTelemetry = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )
        telemetry.error("Oops", kind: "OutOfMemory", stack: "a\nhay\nneedle\nstack")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryErrorEvent.self).model(ofType: TelemetryErrorEvent.self) { event in
            XCTAssertEqual(event.date, 0)
            XCTAssertEqual(event.application?.id, telemetry.applicationID)
            XCTAssertEqual(event.version, telemetry.sdkVersion)
            XCTAssertEqual(event.service, "dd-sdk-ios")
            XCTAssertEqual(event.source, .ios)
            XCTAssertEqual(event.telemetry.message, "Oops")
            XCTAssertEqual(event.telemetry.error?.kind, "OutOfMemory")
            XCTAssertEqual(event.telemetry.error?.stack, "a\nhay\nneedle\nstack")
        }
    }

    func testSendTelemetryDebug_withRUMContext() throws {
        let telemetry: RUMTelemetry = .mockAny(in: core)

        Global.rum.startView(viewController: mockView)
        Global.rum.startUserAction(type: .scroll, name: .mockAny())
        telemetry.debug("telemetry debug")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 3)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryDebugEvent.self).model(ofType: TelemetryDebugEvent.self) { event in
            XCTAssertEqual(event.telemetry.message, "telemetry debug")
            XCTAssertValidRumUUID(event.action?.id)
            XCTAssertValidRumUUID(event.view?.id)
            XCTAssertValidRumUUID(event.session?.id)
        }
    }

    func testSendTelemetryError_withRUMContext() throws {
        let telemetry: RUMTelemetry = .mockAny(in: core)

        Global.rum.startView(viewController: mockView)
        Global.rum.startUserAction(type: .scroll, name: .mockAny())
        telemetry.error("telemetry error")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 3)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryErrorEvent.self).model(ofType: TelemetryErrorEvent.self) { event in
            XCTAssertEqual(event.telemetry.message, "telemetry error")
            XCTAssertValidRumUUID(event.action?.id)
            XCTAssertValidRumUUID(event.view?.id)
            XCTAssertValidRumUUID(event.session?.id)
        }
    }

    func testTelemetryErrorFormatting() {
        class TelemetryTest: Telemetry {
            var record: (message: String, kind: String?, stack: String?)?

            func debug(_ message: String) { }

            func error(_ message: String, kind: String?, stack: String?) {
                record = (message: message, kind: kind, stack: stack)
            }
        }

        let telemetry = TelemetryTest()

        struct SwiftError: Error {
            let description = "error description"
        }

        let swiftError = SwiftError()

        let nsError = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [
                NSLocalizedDescriptionKey: "error description"
            ]
        )

        telemetry.error(swiftError)
        XCTAssertEqual(telemetry.record?.message, #"SwiftError(description: "error description")"#)
        XCTAssertEqual(telemetry.record?.kind, "SwiftError")
        XCTAssertEqual(telemetry.record?.stack, #"SwiftError(description: "error description")"#)

        telemetry.error(nsError)
        XCTAssertEqual(telemetry.record?.message, "error description")
        XCTAssertEqual(telemetry.record?.kind, "custom-domain - 10")
        XCTAssertEqual(
            telemetry.record?.stack,
            """
            Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}
            """
        )

        telemetry.error("swift error", error: swiftError)
        XCTAssertEqual(telemetry.record?.message, #"swift error - SwiftError(description: "error description")"#)

        telemetry.error("ns error", error: nsError)
        XCTAssertEqual(telemetry.record?.message, "ns error - error description")
    }
}
