/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogTrace

class SpanSnapshotTests: XCTestCase {
    func testWhenSpanFinishes_onSpanFinishedCallbackReceivesSnapshot() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        // Given
        let span = tracer.startSpan(operationName: "test.operation")

        // When
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5)
        XCTAssertNotNil(receivedSnapshot)
        XCTAssertEqual(receivedSnapshot?.operationName, "test.operation")
    }

    func testSnapshotCapturesServiceFromTag() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        let span = tracer.startSpan(operationName: "op")
        span.setTag(key: SpanTags.service, value: "custom-service")
        span.finish()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(receivedSnapshot?.service, "custom-service")
    }

    func testSnapshotCapturesResourceFromTag() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        let span = tracer.startSpan(operationName: "op")
        span.setTag(key: SpanTags.resource, value: "GET /users")
        span.finish()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(receivedSnapshot?.resource, "GET /users")
    }

    func testSnapshotCapturesErrorStatus() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        let span = tracer.startSpan(operationName: "op")
        span.setTag(key: OTTags.error, value: true)
        span.finish()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(receivedSnapshot?.isError, true)
    }

    func testSnapshotCapturesSpanKind() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        let span = tracer.startSpan(operationName: "op")
        span.setTag(key: SpanTags.kind, value: "client")
        span.finish()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(receivedSnapshot?.spanKind, "client")
    }

    func testSnapshotCapturesHTTPStatusCode() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        let span = tracer.startSpan(operationName: "op")
        span.setTag(key: OTTags.httpStatusCode, value: 404)
        span.finish()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(receivedSnapshot?.httpStatusCode, 404)
    }

    func testSnapshotIsTopLevelWhenNoParent() {
        let snapshotExpectation = expectation(description: "snapshot received")
        var receivedSnapshot: SpanSnapshot?

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        tracer.onSpanFinished = { snapshot in
            receivedSnapshot = snapshot
            snapshotExpectation.fulfill()
        }

        let span = tracer.startRootSpan(operationName: "root")
        span.finish()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(receivedSnapshot?.isTopLevel, true)
        XCTAssertNil(receivedSnapshot?.parentSpanID)
    }

    func testSnapshotIsCalledBeforeSamplingCheck() {
        let snapshotExpectation = expectation(description: "snapshot received")

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            samplingProvider: TracerSamplerProviderMock.mockRejectAll()
        )
        tracer.onSpanFinished = { _ in
            snapshotExpectation.fulfill()
        }

        let span = tracer.startSpan(operationName: "sampled-out")
        span.finish()

        waitForExpectations(timeout: 0.5)
    }

    func testWhenOnSpanFinishedIsNil_noSnapshotIsCreated() {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        // onSpanFinished is nil by default

        let span = tracer.startSpan(operationName: "op")
        span.finish()

        // No crash, no snapshot - this is a no-op path
    }
}
