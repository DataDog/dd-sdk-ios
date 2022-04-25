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

    func testTelemetryErrorFormatting() {
        class TelemetryTest: Telemetry {
            var record: (message: String, kind: String?, stack: String?)?

            func debug(id: String, message: String) { }

            func error(id: String, message: String, kind: String?, stack: String?) {
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
    func testSendTelemetry_discardDuplicates() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny()

        // When
        telemetry.debug(id: "0", message: "telemetry debug 0")
        telemetry.error(id: "0", message: "telemetry debug 1", kind: nil, stack: nil)
        telemetry.debug(id: "0", message: "telemetry debug 2")
        telemetry.debug(id: "1", message: "telemetry debug 3")

        for _ in 0...10 {
            // telemetry id is composed of the file, line number, and message
            telemetry.debug("telemetry debug 4")
        }

        for index in 5...10 {
            // telemetry id is composed of the file, line number, and message
            telemetry.debug("telemetry debug \(index)")
        }

        telemetry.debug("telemetry debug 11")

        // Then
        let events = try RUMFeature.waitAndReturnRUMEventMatchers(count: 10).compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 10)
        XCTAssertEqual(events[0].telemetry.message, "telemetry debug 0")
        XCTAssertEqual(events[1].telemetry.message, "telemetry debug 3")
        XCTAssertEqual(events[2].telemetry.message, "telemetry debug 4")
        XCTAssertEqual(events[3].telemetry.message, "telemetry debug 5")
        XCTAssertEqual(events.last?.telemetry.message, "telemetry debug 11")
    }

    func testSendTelemetry_toSessionLimit() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny()

        // When
        // sends 101 telemetry events
        for index in 0...RUMTelemetry.MaxEventsPerSessions {
            telemetry.debug(id: "\(index)", message: "telemetry debug")
        }

        // Then
        let eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 100)
        let events = try eventMatchers.compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 100)
    }

    func testSampledTelemetry_rejectAll() throws {
        // Given
        let telemetry: RUMTelemetry = .mockWith(sampler: .mockRejectAll())

        // When
        // sends 10 telemetry events
        for index in 0..<10 {
            telemetry.debug(id: "\(index)", message: "telemetry debug")
        }

        // Then
        let eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 0)
        let events = try eventMatchers.compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 0)
    }

    func testSendTelemetry_resetAfterSessionExpire() throws {
        // Given
        let monitor = try XCTUnwrap(Global.rum as? RUMMonitor, "Global RUM monitor must be of type `RUMMonitor`")
        let telemetry: RUMTelemetry = .mockAny()
        var currentTime = Date()

        // When
        let view = createMockViewInWindow()
        telemetry.debug(id: "0", message: "telemetry debug")
        monitor.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: view))

        // push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        monitor.process(command: RUMAddUserActionCommand.mockWith(time: currentTime))
        telemetry.debug(id: "0", message: "telemetry debug")

        // Then
        let eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 2)
        let events = try eventMatchers.compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Thread safety

    func testSendTelemetryAndReset_onAnyThread() throws {
        let monitor = try XCTUnwrap(Global.rum as? RUMMonitor, "Global RUM monitor must be of type `RUMMonitor`")
        let telemetry: RUMTelemetry = .mockAny()

        let view = createMockViewInWindow()
        monitor.process(command: RUMStartViewCommand.mockWith(time: .init(), identity: view))

        // timeoffset will be incremented to force session renewal
        let timeoffset = ValuePublisher(initialValue: RUMSessionScope.Constants.sessionMaxDuration)

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { telemetry.debug(id: .mockRandom(), message: "telemetry debug") },
                { telemetry.error(id: .mockRandom(), message: "telemetry error", kind: nil, stack: nil) },
                {
                    let offset = timeoffset.currentValue
                    let time = Date(timeIntervalSinceNow: offset)
                    monitor.process(command: RUMAddUserActionCommand.mockWith(time: time))
                    timeoffset.publishSync(offset + RUMSessionScope.Constants.sessionMaxDuration)
                }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace
    }
}
