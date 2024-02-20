/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import OpenTelemetryApi

@testable import DatadogLogs
@testable import DatadogTrace

final class OTelSpanTests: XCTestCase {
    func testAddEvent() {
        let core = DatadogCoreProxy()
        defer { core.flushAndTearDown() }

        Logs.enable(in: core)
        Trace.enable(in: core)

        // Given
        OpenTelemetry.registerTracerProvider(
            tracerProvider: OTelTracerProvider(in: core)
        )

        let tracer = OpenTelemetry
            .instance
            .tracerProvider
            .get(instrumentationName: "", instrumentationVersion: nil)

        let span = tracer
            .spanBuilder(spanName: "OperationName")
            .startSpan()

        // When
        let attributes: [String: OpenTelemetryApi.AttributeValue] = .leafMock()
        span.addEvent(name: "Otel Span Event", attributes: attributes, timestamp: Date())

        // Then
        let logs: [LogEvent] = core.waitAndReturnEvents(ofFeature: LogsFeature.name, ofType: LogEvent.self)
        XCTAssertEqual(logs.count, 1)

        let expectedAttributes: [String: Encodable] = [
            "string": "value",
            "bool": "true",
            "int": "2",
            "double": "2.0",
            "stringArray.0": "value1",
            "stringArray.1": "value2",
            "boolArray.0": "true",
            "boolArray.1": "false",
            "intArray.0": "1",
            "intArray.1": "2",
            "doubleArray.0": "1.0",
            "doubleArray.1": "2.0"
        ]
        DDAssertJSONEqual(AnyEncodable(expectedAttributes), AnyEncodable(logs[0].attributes.userAttributes))
    }
}

extension Dictionary where Key == String, Value == OpenTelemetryApi.AttributeValue {
    static func mock() -> Self {
        return [
            "string": .string("value"),
            "bool": .bool(true),
            "int": .int(2),
            "double": .double(2.0),
            "stringArray": .stringArray(["value1", "value2"]),
            "boolArray": .boolArray([true, false]),
            "intArray": .intArray([1, 2]),
            "doubleArray": .doubleArray([1.0, 2.0]),
            "set": .set(.init(labels: .leafMock()))
        ]
    }

    static func leafMock() -> Self {
        return [
            "string": .string("value"),
            "bool": .bool(true),
            "int": .int(2),
            "double": .double(2.0),
            "stringArray": .stringArray(["value1", "value2"]),
            "boolArray": .boolArray([true, false]),
            "intArray": .intArray([1, 2]),
            "doubleArray": .doubleArray([1.0, 2.0])
        ]
    }
}
