/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

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

    func testSpanOperationNameAttribute() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "https://httpbin.org/get").startSpan()

        // When
        span.setAttribute(key: "operation.name", value: .string("GET"))
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!
        XCTAssertEqual(recordedSpan.resource, "https://httpbin.org/get")
        XCTAssertEqual(recordedSpan.operationName, "GET")
    }

    func testSpanServiceNameDefault() {
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
        XCTAssertEqual(recordedSpan.serviceName, "abc")
    }

    func testSpanServiceNameAttribute() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "OperationName").startSpan()

        // When
        span.setAttribute(key: "service.name", value: .string("ServiceName"))
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!
        XCTAssertEqual(recordedSpan.serviceName, "ServiceName")
    }

    func testSpanResourceNameAttribute() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "OperationName").startSpan()

        // When
        span.setAttribute(key: "resource.name", value: "ResourceName")
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)
        let recordedSpan = recordedSpans.first!
        XCTAssertEqual(recordedSpan.resource, "ResourceName")
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
            "span.kind": "internal",
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
        XCTAssertNil(parent.parentID)
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
        XCTAssertNil(parent.parentID)
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
        XCTAssertNil(parent.parentID)
        XCTAssertEqual(child.parentID, nil)
    }

    func testSetActive_givenParentSpan() {
        let writeSpanExpectation = expectation(description: "write span event")
         writeSpanExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let parentSpan = tracer.spanBuilder(spanName: "Parent").setActive(true).startSpan()
        let childSpan = tracer.spanBuilder(spanName: "Child").startSpan()

        // When
        childSpan.end()
        parentSpan.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 2)
        let child = recordedSpans.first!
        let parent = recordedSpans.last!
        XCTAssertEqual(child.traceID, parent.traceID)
        XCTAssertNil(parent.parentID)
        XCTAssertEqual(child.parentID, parent.spanID)
    }

    func testParentIds_givenDisjointSpans() {
        let writeSpanExpectation = expectation(description: "write span event")
        writeSpanExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span1 = tracer.spanBuilder(spanName: "Span1").startSpan()
        let span2 = tracer.spanBuilder(spanName: "Span2").startSpan()

        // When
        span2.end()
        span1.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 2)
        let span1Recorded = recordedSpans.first!
        let span2Recorded = recordedSpans.last!

        XCTAssertEqual(span1Recorded.parentID, nil)
        XCTAssertEqual(span2Recorded.parentID, nil)
        XCTAssertNotEqual(span1Recorded.traceID, span2Recorded.traceID)
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
            "span.kind": "internal",
        ]
        DDAssertDictionariesEqual(recordedSpan.tags, expectedTags)
    }

    func testStatus_whenStatusIsNotSet() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "Span").startSpan()

        // When
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)

        let recordedSpan = recordedSpans.first!
        XCTAssertFalse(recordedSpan.isError)
        XCTAssertEqual(recordedSpan.tags["error.type"], nil)
        XCTAssertEqual(recordedSpan.tags["error.message"], nil)
        XCTAssertEqual(recordedSpan.tags["error.stack"], nil)
    }

    func testStatus_whenStatusIsOk() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "Span").startSpan()

        // When
        span.status = .ok
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)

        let recordedSpan = recordedSpans.first!
        XCTAssertFalse(recordedSpan.isError)
        XCTAssertEqual(recordedSpan.tags["error.type"], nil)
        XCTAssertEqual(recordedSpan.tags["error.message"], nil)
    }

    func testStatus_whenStatusIsErrorWithMessage() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "Span").startSpan()

        // When
        span.status = .error(description: "error description")
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)

        let recordedSpan = recordedSpans.first!
        XCTAssertTrue(recordedSpan.isError)
        XCTAssertEqual(recordedSpan.tags["error.type"], "")
        // In OLTP world, error message is set as `error.message`
        // but during the migration we want to keep it as `error.msg`.
        // https://github.com/open-telemetry/opentelemetry-proto/blob/724e427879e3d2bae2edc0218fff06e37b9eb46e/opentelemetry/proto/trace/v1/trace.proto#L264
        XCTAssertEqual(recordedSpan.tags["error.msg"], "error description")
    }

    func testStatus_givenStatusOk_whenSetStatusCalledWithErrorAndUnset() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "Span").startSpan()
        span.status = .ok

        // When
        span.status = .error(description: "error description")
        span.status = .unset
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)

        let recordedSpan = recordedSpans.first!
        XCTAssertFalse(recordedSpan.isError)
        XCTAssertEqual(recordedSpan.tags["error.type"], nil)
        XCTAssertEqual(recordedSpan.tags["error.msg"], nil)
    }

    func testStatus_givenStatusError_whenSetStatusCalledWithUnset() {
        let writeSpanExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(expectation: writeSpanExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.spanBuilder(spanName: "Span").startSpan()
        span.status = .error(description: "error description")

        // When
        span.status = .unset
        span.end()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let recordedSpans = core.spans()
        XCTAssertEqual(recordedSpans.count, 1)

        let recordedSpan = recordedSpans.first!
        XCTAssertTrue(recordedSpan.isError)
        XCTAssertEqual(recordedSpan.tags["error.type"], "")
        XCTAssertEqual(recordedSpan.tags["error.msg"], "error description")
    }
}

extension PassthroughCoreMock {
    func spans() -> [SpanEvent] {
        let events: [SpanEventsEnvelope] = self.events()
        return events.flatMap { $0.spans }
    }
}
