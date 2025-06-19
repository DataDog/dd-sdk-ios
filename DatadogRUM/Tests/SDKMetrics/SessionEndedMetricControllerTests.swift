/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class SessionEndedMetricControllerTests: XCTestCase {
    private let telemetry = TelemetryMock()

    func testTrackingSingleSessionWithExplicitSessionID() throws {
        let sessionID: RUMUUID = .mockRandom()
        let viewIDs: [String] = .mockRandom(count: 5)
        let errorKinds: [String] = .mockRandom(count: 5)

        // Given
        let controller = SessionEndedMetricController(dependencies: .init(telemetry: telemetry, applicationID: .mockRandom(), sampleRate: 4.2))
        controller.startMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom(), tracksBackgroundEvents: .mockRandom())

        // When
        viewIDs.forEach { controller.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: $0), instrumentationType: nil, in: sessionID) }
        errorKinds.forEach { controller.track(sdkErrorKind: $0, in: sessionID) }
        controller.track(missedEventType: .action, in: sessionID)
        controller.trackWasStopped(sessionID: sessionID)
        controller.endMetric(sessionID: sessionID, with: .mockRandom())

        // Then
        let metric = try XCTUnwrap(telemetry.messages.lastSessionEndedMetric)
        XCTAssertEqual(metric.viewsCount.total, viewIDs.count)
        XCTAssertEqual(metric.sdkErrorsCount.total, errorKinds.count)
        XCTAssertEqual(metric.noViewEventsCount.actions, 1)
        XCTAssertEqual(metric.wasStopped, true)
        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: SessionEndedMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 4.2)
    }

    func testTrackingMultipleSessionsWithExplicitSessionID() throws {
        let sessionID1: RUMUUID = .mockRandom()
        let sessionID2: RUMUUID = .mockRandom()

        // When
        let controller = SessionEndedMetricController(dependencies: .init(telemetry: telemetry, applicationID: .mockRandom(), sampleRate: 100))
        controller.startMetric(sessionID: sessionID1, precondition: .mockRandom(), context: .mockRandom(), tracksBackgroundEvents: .mockRandom())
        controller.startMetric(sessionID: sessionID2, precondition: .mockRandom(), context: .mockRandom(), tracksBackgroundEvents: .mockRandom())
        // Session 1:
        controller.track(view: .mockRandomWith(sessionID: sessionID1.rawValue), instrumentationType: nil, in: sessionID1)
        controller.track(sdkErrorKind: "error.kind1", in: sessionID1)
        controller.trackWasStopped(sessionID: sessionID1)
        // Session 2:
        controller.track(sdkErrorKind: "error.kind2", in: sessionID2)
        // Send 1st and 2nd:
        controller.endMetric(sessionID: sessionID1, with: .mockRandom())
        let metric1 = try XCTUnwrap(telemetry.messages.lastSessionEndedMetric)
        controller.endMetric(sessionID: sessionID2, with: .mockRandom())
        let metric2 = try XCTUnwrap(telemetry.messages.lastSessionEndedMetric)

        // Then
        XCTAssertEqual(metric1.viewsCount.total, 1)
        XCTAssertEqual(metric1.sdkErrorsCount.total, 1)
        XCTAssertEqual(metric1.sdkErrorsCount.byKind["error_kind1"], 1)
        XCTAssertEqual(metric1.wasStopped, true)

        XCTAssertEqual(metric2.viewsCount.total, 0)
        XCTAssertEqual(metric2.sdkErrorsCount.total, 1)
        XCTAssertEqual(metric2.sdkErrorsCount.byKind["error_kind2"], 1)
        XCTAssertEqual(metric2.wasStopped, false)
    }

    func testTrackingLatestSession() throws {
        let sessionID1: RUMUUID = .mockRandom()
        let sessionID2: RUMUUID = .mockRandom()

        // When
        let controller = SessionEndedMetricController(dependencies: .init(telemetry: telemetry, applicationID: .mockRandom(), sampleRate: 100))
        controller.startMetric(sessionID: sessionID1, precondition: .mockRandom(), context: .mockRandom(), tracksBackgroundEvents: .mockRandom())
        controller.startMetric(sessionID: sessionID2, precondition: .mockRandom(), context: .mockRandom(), tracksBackgroundEvents: .mockRandom())
        // Track latest session (`sessionID: nil`)
        controller.track(view: .mockRandomWith(sessionID: sessionID2.rawValue), instrumentationType: nil, in: nil)
        controller.track(sdkErrorKind: "error.kind1", in: nil)
        controller.track(missedEventType: .resource, in: nil)
        controller.trackWasStopped(sessionID: nil)
        // Send 2nd:
        controller.endMetric(sessionID: sessionID2, with: .mockRandom())
        let metric = try XCTUnwrap(telemetry.messages.lastSessionEndedMetric)

        // Then
        XCTAssertEqual(metric.viewsCount.total, 1)
        XCTAssertEqual(metric.sdkErrorsCount.total, 1)
        XCTAssertEqual(metric.noViewEventsCount.resources, 1)
        XCTAssertEqual(metric.wasStopped, true)
    }

    // MARK: - Thread Safety

    func testTrackingSessionEndedMetricIsThreadSafe() {
        let sessionIDs: [RUMUUID] = .mockRandom(count: 10)
        let controller = SessionEndedMetricController(dependencies: .init(telemetry: telemetry, applicationID: .mockRandom(), sampleRate: 100))

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { controller.startMetric(
                    sessionID: sessionIDs.randomElement()!, precondition: .mockRandom(), context: .mockRandom(), tracksBackgroundEvents: .mockRandom()
                ) },
                { controller.track(view: .mockRandom(), instrumentationType: nil, in: sessionIDs.randomElement()!) },
                { controller.track(sdkErrorKind: .mockRandom(), in: sessionIDs.randomElement()!) },
                { controller.trackWasStopped(sessionID: sessionIDs.randomElement()!) },
                { controller.track(view: .mockRandom(), instrumentationType: nil, in: nil) },
                { controller.track(sdkErrorKind: .mockRandom(), in: nil) },
                { controller.track(missedEventType: .action, in: sessionIDs.randomElement()!) },
                { controller.track(missedEventType: .resource, in: nil) },
                { controller.trackWasStopped(sessionID: nil) },
                { controller.track(uploadQuality: mockRandomAttributes(), in: nil) },
                { controller.endMetric(sessionID: sessionIDs.randomElement()!, with: .mockRandom()) },
            ],
            iterations: 100
        )
        // swiftlint:enable opening_brace
    }
}

// MARK: - Helpers

private extension Array where Element == TelemetryMessage {
    var lastSessionEndedMetric: SessionEndedMetric.Attributes? {
        return lastMetric(named: SessionEndedMetric.Constants.name)?
            .attributes[SessionEndedMetric.Constants.rseKey] as? SessionEndedMetric.Attributes
    }
}
