/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM
@testable import DatadogCore

class RUMEventFileOutputTests: XCTestCase {
    lazy var directory = Directory(url: temporaryDirectory)

    override func setUp() {
        super.setUp()
        CreateTemporaryDirectory()
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
        super.tearDown()
    }

    func testItWritesRUMEventToFileAsJSON() throws {
        let fileCreationDateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC())
        let builder = RUMEventBuilder(eventsMapper: .mockNoOp())
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: PerformancePreset.combining(
                    storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                    uploadPerformance: .noOp
                ),
                dateProvider: fileCreationDateProvider
            ),
            encryption: nil,
            forceNewFile: false
        )

        let dataModel1 = RUMDataModelMock(attribute: "foo", context: RUMEventAttributes(contextInfo: ["custom.attribute": "value"]))
        let dataModel2 = RUMDataModelMock(attribute: "bar")
        let event1 = try XCTUnwrap(builder.build(from: dataModel1))
        let event2 = try XCTUnwrap(builder.build(from: dataModel2))

        writer.write(value: event1)

        fileCreationDateProvider.advance(bySeconds: 1)

        writer.write(value: event2)

        let event1FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC())
        let event1FileEvents = try directory.file(named: event1FileName).readTLVEvents()
        XCTAssertEqual(event1FileEvents.count, 1)

        let event1Matcher = try RUMEventMatcher.fromJSONObjectData(event1FileEvents[0])
        let expectedDatamodel1 = RUMDataModelMock(attribute: "foo", context: RUMEventAttributes(contextInfo: ["custom.attribute": AnyEncodable("value")]))
        DDAssertReflectionEqual(try event1Matcher.model(), expectedDatamodel1)

        let event2FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        let event2FileEvents = try directory.file(named: event2FileName).readTLVEvents()
        XCTAssertEqual(event2FileEvents.count, 1)
        let event2Matcher = try RUMEventMatcher.fromJSONObjectData(event2FileEvents[0])
        DDAssertReflectionEqual(try event2Matcher.model(), dataModel2)

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
