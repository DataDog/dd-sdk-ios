/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDTracerConfigurationTests: XCTestCase {
    private typealias Configuration = DDTracer.Configuration

    func testDefaultTracer() {
        // TODO: RUMM-409 write test
    }

    func testCustomizedTracer() {
        // TODO: RUMM-409 write test
    }
}

class DDTracerErrorTests: XCTestCase {
    func testGivenDatadogNotInitialized_whenInitializingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer.initialize(configuration: .init())
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `DDTracer.initialize()`."
        )
        XCTAssertTrue(tracer is DDNoopTracer)
    }

    func testGivenDatadogNotInitialized_whenUsingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer(spanOutput: SpanOutputMock())
        let fixtures: [(() -> Void, String)] = [
            ({ _ = tracer.startSpan(operationName: .mockAny()) },
             "`Datadog.initialize()` must be called prior to `startSpan(...)`."),
        ]

        fixtures.forEach { tracerMethod, expectedConsoleError in
            tracerMethod()
            XCTAssertEqual(printFunction.printedMessage, "🔥 Datadog SDK usage error: \(expectedConsoleError)")
        }
    }
}
