/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SpanFileOutputTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    // TODO: RUMM-299 Change to `testItWritesSpanToFileAsJSON()` and move JSON assertions to `DDTracerTests` once upload is done
    func testWrittingSpanWithNoParent() throws {
        let queue = DispatchQueue(label: "any")
        let output = SpanFileOutput(
            spanBuilder: .mockWith(
                appContext: .mockWith(bundleVersion: "1.0.0")
            ),
            fileWriter: .mockWrittingToSingleFile(in: temporaryDirectory, on: queue)
        )

        let ddspan: DDSpan = .mockWith(
            context: .mockWith(
                traceID: 29,
                spanID: 1,
                parentSpanID: nil
            ),
            operationName: "operation",
            startTime: .mockDecember15th2019At10AMUTC()
        )

        output.write(ddspan: ddspan, finishTime: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        queue.sync {} // wait on writter queue

        let fileData = try temporaryDirectory.files()[0].read()
        let matcher = try SpanMatcher.fromJSONObjectData(fileData)
        matcher.assertTraceID(equals: "1D")
        matcher.assertSpanID(equals: "1")
        matcher.assertParentSpanID(equals: "0")
        matcher.assertOperationName(equals: "operation")
        matcher.assertStartTime(equals: Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toNanoseconds)
        matcher.assertDuration(equals: 0.5.toNanoseconds)
        matcher.assertValue(forKey: SpanMatcher.JSONKey.applicationVersion, equals: "1.0.0")
    }

    // TODO: RUMM-299 Delete this test as this will be asserted in `DDTracerTests` once upload is done
    func testWrittingSpanWithParent() throws {
        let queue = DispatchQueue(label: "any")
        let output = SpanFileOutput(
            spanBuilder: .mockWith(
                appContext: .mockWith(bundleVersion: "1.0.0")
            ),
            fileWriter: .mockWrittingToSingleFile(in: temporaryDirectory, on: queue)
        )

        let ddspan: DDSpan = .mockWith(
            context: .mockWith(
                traceID: 29,
                spanID: 1,
                parentSpanID: 318
            ),
            operationName: "operation",
            startTime: .mockDecember15th2019At10AMUTC()
        )

        output.write(ddspan: ddspan, finishTime: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        queue.sync {} // wait on writter queue

        let fileData = try temporaryDirectory.files()[0].read()
        let matcher = try SpanMatcher.fromJSONObjectData(fileData)
        matcher.assertTraceID(equals: "1D")
        matcher.assertSpanID(equals: "1")
        matcher.assertParentSpanID(equals: "13E")
        matcher.assertOperationName(equals: "operation")
        matcher.assertStartTime(equals: Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toNanoseconds)
        matcher.assertDuration(equals: 0.5.toNanoseconds)
        matcher.assertValue(forKey: SpanMatcher.JSONKey.applicationVersion, equals: "1.0.0")
    }
}
