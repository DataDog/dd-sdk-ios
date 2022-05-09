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
        let output = SpanFileOutput(
            fileWriter: FileWriter(
                orchestrator: FilesOrchestrator(
                    directory: temporaryDirectory,
                    performance: PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp),
                    dateProvider: SystemDateProvider()
                )
            ),
            environment: .mockRandom()
        )

        let span: SpanEvent = .mockWith(operationName: .mockRandom(), duration: 2)
        output.write(span: span)

        let fileData = try temporaryDirectory.files()[0].read()
        let reader = DataBlockReader(data: fileData)
        let block = try XCTUnwrap(reader.next())
        XCTAssertEqual(block.type, .event)

        let matcher = try SpanMatcher.fromJSONObjectData(block.data)
        XCTAssertEqual(try matcher.operationName(), span.operationName)
        XCTAssertEqual(try matcher.environment(), output.environment)
        XCTAssertEqual(try matcher.duration(), 2_000_000_000)
    }
}
