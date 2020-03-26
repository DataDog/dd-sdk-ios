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

    func testGivenSpanWithNoParent_whenFinished_itIsWrittenToOutput() {
        let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        let spanOutput = SpanOutputMock()
        Datadog.instance = .mockNoOpWith(dateProvider: dateProvider)
        defer { Datadog.instance = nil }

        let tracer = DDTracer(spanOutput: spanOutput)
        let span = tracer.startSpan(operationName: "operation") as? DDSpan
        span?.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))

        let recorded = spanOutput.recorded
        XCTAssertTrue(recorded?.span.tracer() as? DDTracer === tracer)
        XCTAssertEqual(recorded?.span.operationName, "operation")
        XCTAssertEqual(recorded?.span.startTime, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(recorded?.finishTime, .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
    }

    func testGivenSpanWithParent_whenFinished_itIsWrittenToOutput() {
        let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        let spanOutput = SpanOutputMock()
        Datadog.instance = .mockNoOpWith(dateProvider: dateProvider)
        defer { Datadog.instance = nil }

        let tracer = DDTracer(spanOutput: spanOutput)
        let parentSpan = tracer.startSpan(operationName: "operation 1") as? DDSpan
        let span = tracer.startSpan(operationName: "operation 2", childOf: parentSpan?.context) as? DDSpan
        span?.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))

        let recorded = spanOutput.recorded
        XCTAssertEqual(recorded?.span.context.dd.traceID, parentSpan?.context.dd.traceID)
        XCTAssertNotEqual(recorded?.span.context.dd.spanID, parentSpan?.context.dd.spanID)
    }

    // MARK: - Initialization

    // TODO: RUMM-339 Move this test to obj-c wrapper tests, similarly to what we do for `DDLoggerBuilderTests`
    func testGivenDatadogNotInitialized_whenUsingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer(spanOutput: SpanOutputMock())
        let fixtures: [(() -> Void, String)] = [
            ({ _ = tracer.startSpan(operationName: .mockAny()) }, "`Datadog.initialize()` must be called prior to `startSpan(...)`.")
        ]

        fixtures.forEach { tracerMethod, expectedConsoleError in
            tracerMethod()
            XCTAssertEqual(printFunction.printedMessage, "🔥 Datadog SDK usage error: \(expectedConsoleError)")
        }
    }
}
