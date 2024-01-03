/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

final class OtelSpanTests: XCTestCase {
    func testSpanResourceNameDefault() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "OperationName").startSpan()

        // When
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)
        let recordedSpan = events.first!.spans.first!
        XCTAssertEqual(recordedSpan.resource, "OperationName")
        XCTAssertEqual(recordedSpan.operationName, "OperationName")
    }

    func testSpanSetName() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "OperationName").startSpan()

        // When
        span.name = "NewOperationName"
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)
        let recordedSpan = events.first!.spans.first!
        XCTAssertEqual(recordedSpan.resource, "NewOperationName")
        XCTAssertEqual(recordedSpan.operationName, "NewOperationName")
    }

    func testSpanEnd() {
        // Given
        let (name, ignoredName) = ("trueName", "invalidName")
        let (code, ignoredCode) = (200, 400)
        let (message, ignoredMessage) = ("message", "ignoredMessage")
        let (attributes, ignoredAttributes) = (["key": "value"], ["ignoredKey": "ignoredValue"])

        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: name).startSpan()
        span.putHttpStatusCode(statusCode: code, reasonPhrase: message)
        for (key, value) in attributes {
            span.setAttribute(key: key, value: value)
        }
        XCTAssertTrue(span.isRecording)

        // When
        span.end()
        XCTAssertFalse(span.isRecording)

        // Then ignores 
        span.name = ignoredName
        span.putHttpStatusCode(statusCode: ignoredCode, reasonPhrase: ignoredMessage)
        for (key, value) in ignoredAttributes {
            span.setAttribute(key: key, value: value)
        }

        span.end()

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)
        let recordedSpan = events.first!.spans.first!

        XCTAssertEqual(recordedSpan.resource, name)
        XCTAssertEqual(recordedSpan.operationName, name)
        let expectedTags = [
            "http.status_code": "200",
            "key": "value",
            "span.kind": "client",
        ]
        XCTAssertEqual(recordedSpan.tags, expectedTags)
    }
}
