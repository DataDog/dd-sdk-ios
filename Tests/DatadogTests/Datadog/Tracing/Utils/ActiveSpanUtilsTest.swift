/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class ActiveSpanUtilsTest: XCTestCase {
    override func tearDown() {
        //Confirm that tests have cleaned up spans
        XCTAssertNil(ActiveSpanUtils.getActiveSpan())
        super.tearDown()
    }

    func testsWhenSpanIsStartedIsAssignedToActiveSpan() throws {
        let tracer = Tracer.mockAny()
        let previousSpan = ActiveSpanUtils.getActiveSpan()
        XCTAssertNil(previousSpan)

        let oneSpan = tracer.startSpan(operationName: .mockAny())
        XCTAssert(ActiveSpanUtils.getActiveSpan()?.ddContext.spanID == oneSpan.dd.ddContext.spanID)
        oneSpan.finish()
        XCTAssertNil(ActiveSpanUtils.getActiveSpan())
    }

    func testsWhenSpanIsFinishedIsRemovedFromActiveSpan() throws {
        let tracer = Tracer.mockAny()
        XCTAssertNil(ActiveSpanUtils.getActiveSpan())

        let oneSpan = tracer.startSpan(operationName: .mockAny())
        XCTAssert(ActiveSpanUtils.getActiveSpan()?.ddContext.spanID == oneSpan.dd.ddContext.spanID)

        oneSpan.finish()
        XCTAssertNil(ActiveSpanUtils.getActiveSpan())
    }

    func testsSpanWithoutParentInheritsActiveSpan() throws {
        let tracer = Tracer.mockAny()
        let firstSpan = tracer.startSpan(operationName: .mockAny())

        let previousActiveSpan = ActiveSpanUtils.getActiveSpan()
        let secondSpan = tracer.startSpan(operationName: .mockAny())

        XCTAssertEqual(secondSpan.dd.ddContext.parentSpanID, previousActiveSpan?.dd.ddContext.spanID)
        XCTAssertEqual(secondSpan.dd.ddContext.spanID,  ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID)
        XCTAssertEqual(secondSpan.dd.ddContext.parentSpanID, firstSpan.dd.ddContext.spanID)

        secondSpan.finish()
        XCTAssertEqual(ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID, firstSpan.dd.ddContext.spanID)
        firstSpan.finish()
        XCTAssertNil(ActiveSpanUtils.getActiveSpan())
    }

    func testsSpanWithParentDoesntInheritActiveSpan() throws {
        let tracer = Tracer.mockAny()
        let oneSpan = tracer.startSpan(operationName: .mockAny())
        let otherSpan = tracer.startSpan(operationName: .mockAny())

        let spanWithParent = tracer.startSpan(operationName: .mockAny(), childOf: oneSpan.context)

        XCTAssertEqual(spanWithParent.dd.ddContext.parentSpanID, oneSpan.dd.ddContext.spanID)
        spanWithParent.finish()
        XCTAssertEqual(ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID, otherSpan.dd.ddContext.spanID)
        oneSpan.finish()
        otherSpan.finish()
    }

    func testActiveSpanIsKeptPerTask() throws {
        let tracer = Tracer.mockAny()
        let oneSpan = tracer.startSpan(operationName: .mockAny())
        let expectation1 = self.expectation(description: "firstSpan created")
        let expectation2 = self.expectation(description: "secondSpan created")

        DispatchQueue.global(qos: .default).async {
            let firstSpan = tracer.startSpan(operationName: .mockAny())
            XCTAssertEqual(ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID, firstSpan.dd.ddContext.spanID)
            expectation1.fulfill()
        }

        DispatchQueue.global(qos: .default).async {
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
            let secondSpan = tracer.startSpan(operationName: .mockAny())
            XCTAssertEqual(ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID, secondSpan.dd.ddContext.spanID)
            expectation2.fulfill()
        }

        XCTAssertEqual(ActiveSpanUtils.getActiveSpan()?.dd.ddContext.spanID, oneSpan.dd.ddContext.spanID)
        waitForExpectations(timeout: 5, handler: nil)
        oneSpan.finish()
    }
}
