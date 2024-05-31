/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class TelemetryInterceptorTests: XCTestCase {
    func testWhenInterceptingErrorTelemetry_itItUpdatesSessionEndedMetric() throws {
        let sessionID = RUMUUID.mockRandom().toRUMDataFormat

        // Given
        let metricController = SessionEndedMetricController(telemetry: NOPTelemetry())
        let interceptor = TelemetryInterecptor(sessionEndedMetric: metricController)

        // When
        metricController.startMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockAny())
        let errorTelemetry: TelemetryMessage = .error(id: .mockAny(), message: .mockAny(), kind: .mockAny(), stack: .mockAny())
        let result = interceptor.receive(message: .telemetry(errorTelemetry), from: NOPDatadogCore())

        // Then
        XCTAssertFalse(result)
        let metricAttributes = try XCTUnwrap(metricController.metric(for: sessionID)?.asMetricAttributes())
        let rse = try XCTUnwrap(metricAttributes[SessionEndedMetric.Constants.rseKey] as? SessionEndedMetric.Attributes)
        XCTAssertEqual(rse.sdkErrorsCount.total, 1)
    }
}
