/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2022 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMTelemetryTests: XCTestCase {
    let core = DatadogCoreMock(context: .mockWith(
        version: .mockRandom(),
        source: .mockAnySource(),
        sdkVersion: .mockRandom()
    ))

    override func setUp() {
        super.setUp()
        let rum: RUMFeature = .mockByRecordingRUMEventMatchers()
        core.register(feature: rum)
    }

    override func tearDown() {
        core.flush()
        super.tearDown()
    }

    // MARK: - Sending Telemetry events

    func testSendTelemetryDebug() throws {
        // Given
        let telemetry: RUMTelemetry = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        telemetry.debug("Hello world!")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryDebugEvent.self).model(ofType: TelemetryDebugEvent.self) { event in
            XCTAssertEqual(event.date, 0)
            XCTAssertEqual(event.version, core.context.sdkVersion)
            XCTAssertEqual(event.service, "dd-sdk-ios")
            XCTAssertEqual(event.source.rawValue, core.context.source)
            XCTAssertEqual(event.telemetry.message, "Hello world!")
        }
    }

    func testSendTelemetryError() throws {
        // Given
        let telemetry: RUMTelemetry = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        telemetry.error("Oops", kind: "OutOfMemory", stack: "a\nhay\nneedle\nstack")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryErrorEvent.self).model(ofType: TelemetryErrorEvent.self) { event in
            XCTAssertEqual(event.date, 0)
            XCTAssertEqual(event.version, core.context.sdkVersion)
            XCTAssertEqual(event.service, "dd-sdk-ios")
            XCTAssertEqual(event.source.rawValue, core.context.source)
            XCTAssertEqual(event.telemetry.message, "Oops")
            XCTAssertEqual(event.telemetry.error?.kind, "OutOfMemory")
            XCTAssertEqual(event.telemetry.error?.stack, "a\nhay\nneedle\nstack")
        }
    }

    func testSendTelemetryDebug_withRUMContext() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny(in: core)
        let applicationId: String = .mockRandom()
        let sessionId: String = .mockRandom()
        let viewId: String = .mockRandom()
        let actionId: String = .mockRandom()

        core.set(feature: "rum", attributes: {[
            RUMMonitor.Attributes.applicationID: applicationId,
            RUMMonitor.Attributes.sessionID: sessionId,
            RUMMonitor.Attributes.viewID: viewId,
            RUMMonitor.Attributes.userActionID: actionId
        ]})

        // When
        telemetry.debug("telemetry debug")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryDebugEvent.self).model(ofType: TelemetryDebugEvent.self) { event in
            XCTAssertEqual(event.telemetry.message, "telemetry debug")
            XCTAssertEqual(event.application?.id, applicationId)
            XCTAssertEqual(event.session?.id, sessionId)
            XCTAssertEqual(event.view?.id, viewId)
            XCTAssertEqual(event.action?.id, actionId)
        }
    }

    func testSendTelemetryError_withRUMContext() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny(in: core)
        let applicationId: String = .mockRandom()
        let sessionId: String = .mockRandom()
        let viewId: String = .mockRandom()
        let actionId: String = .mockRandom()

        core.set(feature: "rum", attributes: {[
            RUMMonitor.Attributes.applicationID: applicationId,
            RUMMonitor.Attributes.sessionID: sessionId,
            RUMMonitor.Attributes.viewID: viewId,
            RUMMonitor.Attributes.userActionID: actionId
        ]})

        // When
        telemetry.error("telemetry error")

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        try rumEventMatchers.lastRUMEvent(ofType: TelemetryErrorEvent.self).model(ofType: TelemetryErrorEvent.self) { event in
            XCTAssertEqual(event.telemetry.message, "telemetry error")
            XCTAssertEqual(event.application?.id, applicationId)
            XCTAssertEqual(event.session?.id, sessionId)
            XCTAssertEqual(event.view?.id, viewId)
            XCTAssertEqual(event.action?.id, actionId)
        }
    }

    func testTelemetryErrorFormatting() {
        class TelemetryTest: Telemetry {
            var record: (id: String, message: String, kind: String?, stack: String?)?

            func debug(id: String, message: String) { }

            func error(id: String, message: String, kind: String?, stack: String?) {
                record = (id: id, message: message, kind: kind, stack: stack)
            }

            func configuration(configuration: FeaturesConfiguration) { }
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

        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error(swiftError)
        #sourceLocation()

        XCTAssertEqual(telemetry.record?.id, #"File.swift:1:SwiftError(description: "error description")"#)
        XCTAssertEqual(telemetry.record?.message, #"SwiftError(description: "error description")"#)
        XCTAssertEqual(telemetry.record?.kind, "SwiftError")
        XCTAssertEqual(telemetry.record?.stack, #"SwiftError(description: "error description")"#)

        #sourceLocation(file: "File.swift", line: 2)
        telemetry.error(nsError)
        #sourceLocation()

        XCTAssertEqual(telemetry.record?.id, "File.swift:2:error description")
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
        let telemetry: RUMTelemetry = .mockAny(in: core)

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
        let events = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 10).compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 10)
        XCTAssertEqual(events[0].telemetry.message, "telemetry debug 0")
        XCTAssertEqual(events[1].telemetry.message, "telemetry debug 3")
        XCTAssertEqual(events[2].telemetry.message, "telemetry debug 4")
        XCTAssertEqual(events[3].telemetry.message, "telemetry debug 5")
        XCTAssertEqual(events.last?.telemetry.message, "telemetry debug 11")
    }

    func testSendTelemetry_toSessionLimit() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny(in: core)

        // When
        // sends 101 telemetry events
        for index in 0...RUMTelemetry.MaxEventsPerSessions {
            telemetry.debug(id: "\(index)", message: "telemetry debug")
        }

        // Then
        let eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 100)
        let events = try eventMatchers.compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 100)
    }

    func testSampledTelemetry_rejectAll() throws {
        // Given
        let telemetry: RUMTelemetry = .mockWith(core: core, sampler: .mockRejectAll())

        // When
        // sends 10 telemetry events
        for index in 0..<10 {
            telemetry.debug(id: "\(index)", message: "telemetry debug")
        }

        // Then
        let eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 0)
        let events = try eventMatchers.compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 0)
    }

    func testSendTelemetry_resetAfterSessionExpire() throws {
        // Given
        let telemetry: RUMTelemetry = .mockAny(in: core)
        let applicationId: String = .mockRandom()

        core.set(feature: "rum", attributes: {[
            RUMMonitor.Attributes.applicationID: applicationId,
            RUMMonitor.Attributes.sessionID: String.mockRandom()
        ]})

        // When
        telemetry.debug(id: "0", message: "telemetry debug")

        core.set(feature: "rum", attributes: {[
            RUMMonitor.Attributes.applicationID: applicationId,
            RUMMonitor.Attributes.sessionID: String.mockRandom() // new session
        ]})

        telemetry.debug(id: "0", message: "telemetry debug")

        // Then
        let eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 2)
        let events = try eventMatchers.compactMap(TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Configuration Telemetry Events

    func testSendTelemetry_sendsConfigurationDelayed() throws {
        // Given
        var delayedDispatch: (() -> Void)?
        let telemetry: RUMTelemetry = .mockWith(
            core: core,
            delayedDispatcher: { block in delayedDispatch = block },
            sampler: .mockKeepAll()
        )

        // When
        telemetry.configuration(configuration: .mockAny())

        // Then immediately
        var eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 0)
        var events = try eventMatchers.compactMap(TelemetryConfigurationEvent.self)
        XCTAssertEqual(events.count, 0)

        // Then later
        delayedDispatch?()

        eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        events = try eventMatchers.compactMap(TelemetryConfigurationEvent.self)
        XCTAssertEqual(events.count, 1)
    }

    func testSendTelemetry_callsTelemetryMapperBeforeSend() throws {
        // Given
        var delayedDispatch: (() -> Void)?
        var mapperCalled = false
        let modifiedEvent = TelemetryConfigurationEvent.mockRandom()
        let telemetry: RUMTelemetry = .mockWith(
            core: core,
            configurationEventMapper: { event in
                mapperCalled = true
                return modifiedEvent
            },
            delayedDispatcher: { block in delayedDispatch = block },
            sampler: .mockKeepAll()
        )

        // When
        telemetry.configuration(configuration: .mockAny())

        // Then immediately
        var eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 0)
        var events = try eventMatchers.compactMap(TelemetryConfigurationEvent.self)
        XCTAssertFalse(mapperCalled)
        XCTAssertEqual(events.count, 0)

        // Then later
        delayedDispatch?()

        eventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(in: core, count: 1)
        events = try eventMatchers.compactMap(TelemetryConfigurationEvent.self)
        XCTAssertTrue(mapperCalled)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], modifiedEvent)
    }

    // MARK: - Thread safety

    func testSendTelemetryAndReset_onAnyThread() throws {
        let telemetry: RUMTelemetry = .mockAny(in: core)

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { telemetry.debug(id: .mockRandom(), message: "telemetry debug") },
                { telemetry.error(id: .mockRandom(), message: "telemetry error", kind: nil, stack: nil) },
                {
                    self.core.set(feature: "rum", attributes: {[
                        RUMMonitor.Attributes.applicationID: String.mockRandom(),
                        RUMMonitor.Attributes.sessionID: String.mockRandom(),
                        RUMMonitor.Attributes.viewID: String.mockRandom(),
                        RUMMonitor.Attributes.userActionID: String.mockRandom()
                    ]})
                }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace
    }
}
