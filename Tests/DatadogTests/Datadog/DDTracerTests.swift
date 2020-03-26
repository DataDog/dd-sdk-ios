/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import OpenTracing
@testable import Datadog

class DDTracerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        super.tearDown()
    }

    func testItStartsSpanWithNoParent() {
        let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        Datadog.instance = .mockNoOpWith(dateProvider: dateProvider)
        defer { Datadog.instance = nil }

        let tracer = DDTracer()
        let span = tracer.startSpan(operationName: "operation") as? DDSpan

        XCTAssertTrue(span?.tracer() as? DDTracer === tracer)
        XCTAssertEqual(span?.operationName, "operation")
        XCTAssertEqual(span?.startTime, .mockDecember15th2019At10AMUTC())
    }

    func testItStartsSpanWithParent() {
        let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        Datadog.instance = .mockNoOpWith(dateProvider: dateProvider)
        defer { Datadog.instance = nil }

        let tracer = DDTracer()
        let parentSpan = tracer.startSpan(operationName: "operation 1") as? DDSpan
        let span = tracer.startSpan(operationName: "operation 2", childOf: parentSpan?.context) as? DDSpan

        XCTAssertTrue(span?.tracer() as? DDTracer === tracer)
        XCTAssertEqual(span?.operationName, "operation 2")
        XCTAssertEqual(span?.startTime, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual((span?.context as? DDSpanContext)?.traceID, (parentSpan?.context as? DDSpanContext)?.traceID)
        XCTAssertNotEqual((span?.context as? DDSpanContext)?.spanID, (parentSpan?.context as? DDSpanContext)?.spanID)
    }

    // MARK: - Initialization

    // TODO: RUMM-339 Move this test to obj-c wrapper tests, similarly to what we do for `DDLoggerBuilderTests`
    func testGivenDatadogNotInitialized_whenUsingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer()
        let fixtures: [(() -> Void, String)] = [
            ({ _ = tracer.startSpan(operationName: .mockAny()) }, "`Datadog.initialize()` must be called prior to `startSpan(...)`.")
        ]

        fixtures.forEach { tracerMethod, expectedConsoleError in
            tracerMethod()
            XCTAssertEqual(printFunction.printedMessage, "🔥 Datadog SDK usage error: \(expectedConsoleError)")
        }
    }
}
