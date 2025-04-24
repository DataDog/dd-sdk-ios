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
        defer { XCTAssertNoThrow(try core.flushAndTearDown()) }

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
        XCTAssertEqual(logs.count, 0)
    }

    func testContextProviderSetActive_givenParentSpan() throws {
        let core = DatadogCoreProxy()
        defer { XCTAssertNoThrow(try core.flushAndTearDown())}

        Trace.enable(in: core)

        // Given
        OpenTelemetry.registerTracerProvider(
            tracerProvider: OTelTracerProvider(in: core)
        )

        let tracer = OpenTelemetry
            .instance
            .tracerProvider
            .get(instrumentationName: "", instrumentationVersion: nil)

        let parentSpan = tracer
            .spanBuilder(spanName: "ParentSpan")
            .startSpan()

        // When
        OpenTelemetry.instance.contextProvider.setActiveSpan(parentSpan)

        let childSpan = tracer
            .spanBuilder(spanName: "ChildSpan")
            .startSpan()

        childSpan.end()
        parentSpan.end()

        // Then
        let spans = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(spans.count, 2)

        let childSpanMatcher = spans[0]
        let parentSpanMatcher = spans[1]

        XCTAssertEqual(try parentSpanMatcher.traceID(), try childSpanMatcher.traceID())
        XCTAssertEqual(try parentSpanMatcher.spanID(), try childSpanMatcher.parentSpanID())
    }
}

extension Dictionary where Key == String, Value == OpenTelemetryApi.AttributeValue {
    static func mock() -> Self {
        return [
            "string": .string("value"),
            "bool": .bool(true),
            "int": .int(2),
            "double": .double(2.0),
            "stringArray": .array(.init(values: [.string("value1"), .string("value2")])),
            "boolArray": .array(.init(values: [.bool(true), .bool(false)])),
            "intArray": .array(.init(values: [.int(1), .int(2)])),
            "doubleArray": .array(.init(values: [.double(1.0), .double(2.0)])),
            "set": .set(.init(labels: .leafMock()))
        ]
    }

    static func leafMock() -> Self {
        return [
            "string": .string("value"),
            "bool": .bool(true),
            "int": .int(2),
            "double": .double(2.0),
            "stringArray": .array(.init(values: [.string("value1"), .string("value2")])),
            "boolArray": .array(.init(values: [.bool(true), .bool(false)])),
            "intArray": .array(.init(values: [.int(1), .int(2)])),
            "doubleArray": .array(.init(values: [.double(1.0), .double(2.0)]))
        ]
    }
}
