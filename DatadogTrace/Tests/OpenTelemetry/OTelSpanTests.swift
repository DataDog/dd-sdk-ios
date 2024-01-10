/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import OpenTelemetryApi

@testable import DatadogTrace

final class OTelSpanTests: XCTestCase {
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
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!
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
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!
        XCTAssertEqual(recordedSpan.resource, "NewOperationName")
        XCTAssertEqual(recordedSpan.operationName, "NewOperationName")
    }

    func testSpanEnd() {
        // Given
        let (name, ignoredName) = ("trueName", "invalidName")
        let (attributes, ignoredAttributes) = (["key": "value"], ["ignoredKey": "ignoredValue"])

        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: name).startSpan()
        for (key, value) in attributes {
            span.setAttribute(key: key, value: value)
        }
        XCTAssertTrue(span.isRecording)

        // When
        span.end()
        XCTAssertFalse(span.isRecording)

        // Then ignores
        span.name = ignoredName
        for (key, value) in ignoredAttributes {
            span.setAttribute(key: key, value: value)
        }

        span.end()

        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!

        XCTAssertEqual(recordedSpan.resource, name)
        XCTAssertEqual(recordedSpan.operationName, name)
        let expectedTags = [
            "key": "value",
            "span.kind": "client",
        ]
        DDAssertDictionariesEqual(recordedSpan.tags, expectedTags)
    }

    func testSetParentSpan() {
        let writeSpanExpectation = expectation(description: "write span event")
        writeSpanExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let parentSpan = tracer.spanBuilder(spanName: "Parent").startSpan()
        _ = tracer.spanBuilder(spanName: "Noise").startSpan()
        let childSpan = tracer.spanBuilder(spanName: "Child").setParent(parentSpan).startSpan()

        // When
        childSpan.end()
        parentSpan.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 2)
        let child = recordedSpans.first!
        let parent = recordedSpans.last!
        XCTAssertEqual(parent.parentID, nil)
        XCTAssertEqual(child.parentID, parent.spanID)
    }

    func testSetParentContext() {
        let writeSpanExpectation = expectation(description: "write span event")
        writeSpanExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let parentSpan = tracer.spanBuilder(spanName: "Parent").startSpan()
        _ = tracer.spanBuilder(spanName: "Noise").startSpan()
        let childSpan = tracer.spanBuilder(spanName: "Child").setParent(parentSpan.context).startSpan()

        // When
        childSpan.end()
        parentSpan.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 2)
        let child = recordedSpans.first!
        let parent = recordedSpans.last!
        XCTAssertEqual(parent.parentID, nil)
        XCTAssertEqual(child.parentID, parent.spanID)
    }

    func testSetNoParent() {
        let writeSpanExpectation = expectation(description: "write span event")
        writeSpanExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let parentSpan = tracer.spanBuilder(spanName: "Parent").startSpan()
        _ = tracer.spanBuilder(spanName: "Noise").startSpan()
        let childSpan = tracer.spanBuilder(spanName: "Child").setNoParent().startSpan()

        // When
        childSpan.end()
        parentSpan.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 2)
        let child = recordedSpans.first!
        let parent = recordedSpans.last!
        XCTAssertEqual(parent.parentID, nil)
        XCTAssertEqual(child.parentID, nil)
    }

    func testSetAttribute() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "Span").startSpan()

        // When
        span.setAttribute(key: "key", value: .bool(true))
        span.setAttribute(key: "key2", value: .string("value2"))
        span.setAttribute(key: "key3", value: .int(3))
        span.setAttribute(key: "key4", value: .double(4.0))

        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!
        let expectedTags =
        [
            "key": "true",
            "key2": "value2",
            "key3": "3",
            "key4": "4.0",
            "span.kind": "client",
        ]
        DDAssertDictionariesEqual(recordedSpan.tags, expectedTags)
    }
}

extension PassthroughCoreMock {
    func spans() -> [SpanEvent] {
        let events: [SpanEventsEnvelope] = self.events()
        return events.flatMap { $0.spans }
    }
}
