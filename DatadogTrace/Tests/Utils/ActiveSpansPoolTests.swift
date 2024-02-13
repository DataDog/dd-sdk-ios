/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

class ActiveSpansPoolTests: XCTestCase {
    private var core: DatadogCoreProtocol! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = PassthroughCoreMock()
    }

    override func tearDown() {
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
    }

    func testsWhenSpanIsFinishedIsRemovedFromActiveSpan() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        XCTAssertNil(tracer.activeSpan)

        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        XCTAssert(tracer.activeSpan?.dd.ddContext.spanID == oneSpan.dd.ddContext.spanID)

        oneSpan.finish()
        XCTAssertNil(tracer.activeSpan)
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
    }

    func testActiveSpanIsKeptPerTask() throws {
        let tracer = DatadogTracer.mockAny(in: core)
        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        var firstSpan: OTSpan?
        var secondSpan: OTSpan?

        let expectation1 = self.expectation(description: "firstSpan created")
        let expectation2 = self.expectation(description: "secondSpan created")

        DispatchQueue.global(qos: .default).async {
            firstSpan = tracer.startSpan(operationName: .mockAny()).setActive()
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, firstSpan!.dd.ddContext.spanID)
            expectation1.fulfill()
        }

        DispatchQueue.global(qos: .default).async {
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
            secondSpan = tracer.startSpan(operationName: .mockAny()).setActive()
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, secondSpan!.dd.ddContext.spanID)
            expectation2.fulfill()
        }

        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
        waitForExpectations(timeout: 5, handler: nil)
        oneSpan.finish()
        firstSpan?.finish()
        secondSpan?.finish()
    }

    func testsSetActiveSpanCalledMultipleTimes() throws {
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
    }
}
