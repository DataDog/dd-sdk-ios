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

    func testWhenMetricIsStarted_itCanBeRetrievedByID() throws {
        let controller = SessionEndedMetricController(telemetry: telemetry)

        // When
        let sessionID1: String = .mockRandom()
        let sessionID2: String = .mockRandom()
        controller.startMetric(sessionID: sessionID1, precondition: .mockRandom(), context: .mockRandom())
        controller.startMetric(sessionID: sessionID2, precondition: .mockRandom(), context: .mockRandom())

        // Then
        let metric1 = try XCTUnwrap(controller.metric(for: sessionID1))
        let metric2 = try XCTUnwrap(controller.metric(for: sessionID2))
        XCTAssertEqual(metric1.sessionID, sessionID1)
        XCTAssertEqual(metric2.sessionID, sessionID2)
    }

    func testWhenMetricIsStarted_itCanBeRetrievedAsLatest() throws {
        let controller = SessionEndedMetricController(telemetry: telemetry)

        // When
        let sessionID1: String = .mockRandom()
        let sessionID2: String = .mockRandom()
        controller.startMetric(sessionID: sessionID1, precondition: .mockRandom(), context: .mockRandom())
        controller.startMetric(sessionID: sessionID2, precondition: .mockRandom(), context: .mockRandom())

        // Then
        XCTAssertEqual(controller.latestMetric?.sessionID, sessionID2)
        controller.endMetric(sessionID: sessionID2)
        XCTAssertEqual(controller.latestMetric?.sessionID, sessionID1)
        controller.endMetric(sessionID: sessionID1)
        XCTAssertNil(controller.latestMetric)
    }

    func testWhenMetricIsEnded_itIsSentToTelemetry() throws {
        let sessionID: String = .mockRandom()
        let controller = SessionEndedMetricController(telemetry: telemetry)
        controller.startMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        controller.endMetric(sessionID: sessionID)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: SessionEndedMetric.Constants.name))
        XCTAssertEqual(metric.attributes[SDKMetricFields.typeKey] as? String, SessionEndedMetric.Constants.typeValue)
        XCTAssertEqual(metric.attributes[SDKMetricFields.sessionIDOverrideKey] as? String, sessionID)
    }

    func testAfterMetricIsEnded_itCanNoLongerBeRetrieved() throws {
        let sessionID: String = .mockRandom()
        let controller = SessionEndedMetricController(telemetry: telemetry)
        controller.startMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        XCTAssertNotNil(controller.metric(for: sessionID))
        controller.endMetric(sessionID: sessionID)

        // Then
        XCTAssertNil(controller.metric(for: sessionID))
        XCTAssertNil(controller.latestMetric)
    }

    func testWhenSessionIsSampled_itDoesNotTrackMetric() throws {
        let controller = SessionEndedMetricController(telemetry: telemetry)

        // When
        let rejectedSessionID = RUMUUID.nullUUID.toRUMDataFormat
        controller.startMetric(sessionID: rejectedSessionID, precondition: .mockRandom(), context: .mockRandom())

        // Then
        XCTAssertNil(controller.metric(for: rejectedSessionID))
        XCTAssertNil(controller.latestMetric)

        controller.endMetric(sessionID: rejectedSessionID)
        XCTAssertTrue(telemetry.messages.isEmpty)
    }

    // MARK: - Thread Safety

    func testTrackingSessionEndedMetricIsThreadSafe() {
        let sessionIDs: [String] = .mockRandom(count: 10)
        let controller = SessionEndedMetricController(telemetry: telemetry)

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { controller.startMetric(
                    sessionID: sessionIDs.randomElement()!, precondition: .mockRandom(), context: .mockRandom()
                ) },
                { _ = controller.metric(for: sessionIDs.randomElement()!) },
                {
                    _ = controller.metric(for: sessionIDs.randomElement()!)?.track(view: .mockRandom())
                },
                {
                    _ = controller.metric(for: sessionIDs.randomElement()!)?.track(sdkErrorKind: .mockRandom())
                },
                {
                    _ = controller.metric(for: sessionIDs.randomElement()!)?.trackWasStopped()
                },
                { controller.endMetric(sessionID: sessionIDs.randomElement()!) },
            ],
            iterations: 100
        )
        // swiftlint:enable opening_brace
    }
}
