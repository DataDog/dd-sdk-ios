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

    func testItWritesSpanToFileAsJSON() throws {
        let queue = DispatchQueue(label: "any")
        let output = SpanFileOutput(
            spanBuilder: .mockAny(),
            fileWriter: FileWriter(
                dataFormat: TracingFeature.Storage.dataFormat,
                orchestrator: FilesOrchestrator(
                    directory: temporaryDirectory,
                    performance: PerformancePreset.default,
                    dateProvider: SystemDateProvider()
                ),
                queue: queue
            )
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
        XCTAssertEqual(try matcher.operationName(), "operation")
    }
}
