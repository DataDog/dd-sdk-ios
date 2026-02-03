/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

@MainActor
class ActiveSpansPoolTests: XCTestCase, Sendable {
    private var core: DatadogCoreProtocol! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() async throws {
        core = PassthroughCoreMock()
    }

    override func tearDown() async throws {
        core = nil
    }

    func testsWhenSpanIsStartedIsAssignedToActiveSpan() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        let previousSpan = tracer.activeSpan
        XCTAssertNil(previousSpan)

        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        XCTAssert(tracer.activeSpan?.dd.ddContext.spanID == oneSpan.dd.ddContext.spanID)
        oneSpan.finish()
        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    func testsWhenSpanIsFinishedIsRemovedFromActiveSpan() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        XCTAssertNil(tracer.activeSpan)

        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        XCTAssert(tracer.activeSpan?.dd.ddContext.spanID == oneSpan.dd.ddContext.spanID)

        oneSpan.finish()
        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    func testsSpanWithoutParentInheritsActiveSpan() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        let firstSpan = tracer.startSpan(operationName: .mockAny())
        firstSpan.setActive()
        let previousActiveSpan = tracer.activeSpan
        let secondSpan = tracer.startSpan(operationName: .mockAny())
        secondSpan.setActive()
        XCTAssertEqual(secondSpan.dd.ddContext.parentSpanID, previousActiveSpan?.dd.ddContext.spanID)
        XCTAssertEqual(secondSpan.dd.ddContext.spanID,  tracer.activeSpan?.dd.ddContext.spanID)
        XCTAssertEqual(secondSpan.dd.ddContext.parentSpanID, firstSpan.dd.ddContext.spanID)

        secondSpan.finish()
        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, firstSpan.dd.ddContext.spanID)
        firstSpan.finish()
        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    func testsSpanWithParentDoesntInheritActiveSpan() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        let oneSpan = tracer.startSpan(operationName: .mockAny())
        let otherSpan = tracer.startSpan(operationName: .mockAny()).setActive()

        let spanWithParent = tracer.startSpan(operationName: .mockAny(), childOf: oneSpan.context)

        XCTAssertEqual(spanWithParent.dd.ddContext.parentSpanID, oneSpan.dd.ddContext.spanID)
        spanWithParent.finish()
        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, otherSpan.dd.ddContext.spanID)
        oneSpan.finish()
        otherSpan.finish()
        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    @available(iOS 13.0, tvOS 13, *)
    func testActiveSpanIsKeptPerTask() async throws {
        let tracer = DatadogTracer.mockAny(in: core)
        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()

        let task1 = Task {
            let firstSpan = tracer.startSpan(operationName: .mockAny()).setActive()
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, firstSpan.dd.ddContext.spanID)
            return firstSpan
        }

        let task2 = Task {
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
            let secondSpan = tracer.startSpan(operationName: .mockAny()).setActive()
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, secondSpan.dd.ddContext.spanID)
            return secondSpan
        }

        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
        let (firstSpan, secondSpan) = try await (task1.value, task2.value)
        oneSpan.finish()
        firstSpan.finish()
        secondSpan.finish()

        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    func testSetActiveSpanCalledMultipleTimesInSingleSpan() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        defer { tracer.activeSpansPool.destroy() }

        let span = tracer.startSpan(operationName: "Reactivated")
        (3...Int.mockRandom(min: 3, max: 10)).forEach { _ in
            span.setActive()
        }

        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, span.dd.ddContext.spanID)

        span.finish()

        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    func testSetActiveSpanCalledMultipleTimesInTwoSpans() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        defer { tracer.activeSpansPool.destroy() }

        let firstSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        firstSpan.setActive()

        let previousActiveSpan = tracer.activeSpan

        let secondSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        firstSpan.setActive()
        secondSpan.setActive()

        XCTAssertEqual(secondSpan.dd.ddContext.parentSpanID, previousActiveSpan?.dd.ddContext.spanID)
        XCTAssertEqual(secondSpan.dd.ddContext.spanID,  tracer.activeSpan?.dd.ddContext.spanID)
        XCTAssertEqual(secondSpan.dd.ddContext.parentSpanID, firstSpan.dd.ddContext.spanID)

        secondSpan.finish()
        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, firstSpan.dd.ddContext.spanID)
        firstSpan.finish()
        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }

    func testSetActive_givenParentWithMultipleChildren() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        defer { tracer.activeSpansPool.destroy() }

        let parentSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        let child1Span = tracer.startSpan(operationName: "Child1").setActive()
        child1Span.finish()

        let child2Span = tracer.startSpan(operationName: "Child2")
        child2Span.finish()
        parentSpan.finish()

        XCTAssertEqual(child1Span.dd.ddContext.traceID, parentSpan.dd.ddContext.traceID)
        XCTAssertEqual(child1Span.dd.ddContext.parentSpanID, parentSpan.dd.ddContext.spanID)
        XCTAssertEqual(child2Span.dd.ddContext.traceID, parentSpan.dd.ddContext.traceID)
        XCTAssertEqual(child2Span.dd.ddContext.parentSpanID, parentSpan.dd.ddContext.spanID)

        XCTAssertNil(tracer.activeSpan)
        XCTAssertTrue(tracer.activeSpansPool.isEmpty)
    }
}
