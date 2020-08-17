/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class ActiveSpansPoolTests: XCTestCase {
    func testsWhenSpanIsStartedIsAssignedToActiveSpan() throws {
        let tracer = Tracer.mockAny()
        let previousSpan = tracer.activeSpan
        XCTAssertNil(previousSpan)

        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        XCTAssert(tracer.activeSpan?.dd.ddContext.spanID == oneSpan.dd.ddContext.spanID)
        oneSpan.finish()
        XCTAssertNil(tracer.activeSpan)
    }

    func testsWhenSpanIsFinishedIsRemovedFromActiveSpan() throws {
        let tracer = Tracer.mockAny()
        XCTAssertNil(tracer.activeSpan)

        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        XCTAssert(tracer.activeSpan?.dd.ddContext.spanID == oneSpan.dd.ddContext.spanID)

        oneSpan.finish()
        XCTAssertNil(tracer.activeSpan)
    }

    func testsSpanWithoutParentInheritsActiveSpan() throws {
        let tracer = Tracer.mockAny()
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

    func testsSpanWithParentDoesntInheritActiveSpan() throws {
        let tracer = Tracer.mockAny()
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
        let tracer = Tracer.mockAny()
        let oneSpan = tracer.startSpan(operationName: .mockAny()).setActive()
        let expectation1 = self.expectation(description: "firstSpan created")
        let expectation2 = self.expectation(description: "secondSpan created")

        DispatchQueue.global(qos: .default).async {
            let firstSpan = tracer.startSpan(operationName: .mockAny()).setActive()
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, firstSpan.dd.ddContext.spanID)
            expectation1.fulfill()
        }

        DispatchQueue.global(qos: .default).async {
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
            let secondSpan = tracer.startSpan(operationName: .mockAny()).setActive()
            XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, secondSpan.dd.ddContext.spanID)
            expectation2.fulfill()
        }

        XCTAssertEqual(tracer.activeSpan?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
        waitForExpectations(timeout: 5, handler: nil)
        oneSpan.finish()
    }

    func testsSetActiveSpanCalledMultipleTimes() throws {
        let tracer = Tracer.mockAny()
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
