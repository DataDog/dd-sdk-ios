/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMEventFileOutputTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItWritesRUMEventToFileAsJSON() throws {
        let fileCreationDateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC())
        let builder = RUMEventBuilder(eventsMapper: .mockNoOp())
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.combining(
                    storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                    uploadPerformance: .noOp
                ),
                dateProvider: fileCreationDateProvider
            )
        )

        let dataModel1 = RUMDataModelMock(attribute: "foo", context: RUMEventAttributes(contextInfo: ["custom.attribute": "value"]))
        let dataModel2 = RUMDataModelMock(attribute: "bar")

        let event1Expectation = XCTestExpectation(description: "Event 1 callback called")
        let event2Expectation = XCTestExpectation(description: "Event 2 callback called")
        var event1: RUMDataModelMock?
        var event2: RUMDataModelMock?
        builder.build(from: dataModel1) { event in
            event1 = event
            event1Expectation.fulfill()
        }
        builder.build(from: dataModel2) { event in
            event2 = event
            event2Expectation.fulfill()
        }
        wait(for: [event1Expectation, event2Expectation], timeout: 0.1)

        event1 = try XCTUnwrap(event1)
        event2 = try XCTUnwrap(event2)

        writer.write(value: event1)

        fileCreationDateProvider.advance(bySeconds: 1)

        writer.write(value: event2)

        let event1FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC())
        let event1FileData = try temporaryDirectory.file(named: event1FileName).read()
        var reader = DataBlockReader(data: event1FileData)
        let eventBlock1 = try XCTUnwrap(reader.next())
        XCTAssertEqual(eventBlock1.type, .event)

        let event1Matcher = try RUMEventMatcher.fromJSONObjectData(eventBlock1.data)

        let expectedDatamodel1 = RUMDataModelMock(attribute: "foo", context: RUMEventAttributes(contextInfo: ["custom.attribute": AnyEncodable("value")]))
        XCTAssertEqual(try event1Matcher.model(), expectedDatamodel1)

        let event2FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        let event2FileData = try temporaryDirectory.file(named: event2FileName).read()
        reader = DataBlockReader(data: event2FileData)
        let eventBlock2 = try XCTUnwrap(reader.next())
        XCTAssertEqual(eventBlock2.type, .event)

        let event2Matcher = try RUMEventMatcher.fromJSONObjectData(eventBlock2.data)
        XCTAssertEqual(try event2Matcher.model(), dataModel2)

        // TODO: RUMM-585 Move assertion of full-json to `RUMMonitorTests`
        // same as we do for `LoggerTests` and `TracerTests`
        try event1Matcher.assertItFullyMatches(
            jsonString: """
            {
                "attribute": "foo",
                "context": {
                    "custom.attribute": "value"
                }
            }
            """
        )

        // TODO: RUMM-638 We also need to test (in `RUMMonitorTests`) that custom user attributes
        // do not overwrite values given by `RUMDataModel`.
    }
}
