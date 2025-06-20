/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

class TelemetryInterceptorTests: XCTestCase {
    private let telemetry = TelemetryMock()

    func testWhenInterceptingErrorTelemetry_itItUpdatesSessionEndedMetric() throws {
        let sessionID: RUMUUID = .mockRandom()

        // Given
        let metricController = SessionEndedMetricController(telemetry: telemetry, sampleRate: 100, tracksBackgroundEvents: .mockAny(), isUsingSceneLifecycle: .mockAny())
        let interceptor = TelemetryInterceptor(sessionEndedMetric: metricController)

        // When
        metricController.startMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockAny())
        let errorTelemetry: TelemetryMessage = .error(id: .mockAny(), message: .mockAny(), kind: .mockAny(), stack: .mockAny())
        let result = interceptor.receive(message: .telemetry(errorTelemetry), from: NOPDatadogCore())
        XCTAssertFalse(result)

        // Then
        metricController.endMetric(sessionID: sessionID, with: .mockRandom())
        let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: SessionEndedMetric.Constants.name))
        let rse = try XCTUnwrap(metric.attributes[SessionEndedMetric.Constants.rseKey] as? SessionEndedMetric.Attributes)
        XCTAssertEqual(rse.sdkErrorsCount.total, 1)
    }

    func testWhenInterceptingUploadQualityMetric_itItUpdatesSessionEndedMetric() throws {
        let sessionID: RUMUUID = .mockRandom()

        // Given
        let metricController = SessionEndedMetricController(telemetry: telemetry, sampleRate: 100, tracksBackgroundEvents: .mockAny(), isUsingSceneLifecycle: .mockAny())
        let interceptor = TelemetryInterceptor(sessionEndedMetric: metricController)

        // When
        metricController.startMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockAny())
        let metricTelemetry: TelemetryMessage = .metric(MetricTelemetry(name: UploadQualityMetric.name, attributes: [UploadQualityMetric.track: "feature"], sampleRate: .mockRandom()))
        let result = interceptor.receive(message: .telemetry(metricTelemetry), from: NOPDatadogCore())
        XCTAssertTrue(result)

        // Then
        metricController.endMetric(sessionID: sessionID, with: .mockRandom())
        let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: SessionEndedMetric.Constants.name))
        let rse = try XCTUnwrap(metric.attributes[SessionEndedMetric.Constants.rseKey] as? SessionEndedMetric.Attributes)
        XCTAssertEqual(rse.uploadQuality["feature"]?.cycleCount, 1)
    }
}
