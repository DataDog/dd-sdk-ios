/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LogFileOutputTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItWritesLogToFileAsJSON() throws {
        let fileCreationDateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC())
        let output = LogFileOutput(
            fileWriter: FileWriter(
                orchestrator: FilesOrchestrator(
                    directory: temporaryDirectory,
                    performance: PerformancePreset.combining(
                        storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                        uploadPerformance: .noOp
                    ),
                    dateProvider: fileCreationDateProvider
                )
            )
        )

        let log1: LogEvent = .mockWith(status: .info, message: "log message 1")
        output.write(log: log1)

        fileCreationDateProvider.advance(bySeconds: 1)

        let log2: LogEvent = .mockWith(status: .warn, message: "log message 2")
        output.write(log: log2)

        let log1FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC())
        let log1FileStream = try temporaryDirectory.file(named: log1FileName).stream()
        var reader = DataBlockReader(input: log1FileStream)
        let logBlock1 = try XCTUnwrap(reader.next())
        XCTAssertEqual(logBlock1.type, .event)

        let log1Matcher = try LogMatcher.fromJSONObjectData(logBlock1.data)
        log1Matcher.assertStatus(equals: "info")
        log1Matcher.assertMessage(equals: "log message 1")

        let log2FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        let log2FileStream = try temporaryDirectory.file(named: log2FileName).stream()
        reader = DataBlockReader(input: log2FileStream)
        let logBlock2 = try XCTUnwrap(reader.next())
        XCTAssertEqual(logBlock2.type, .event)

        let log2Matcher = try LogMatcher.fromJSONObjectData(logBlock2.data)
        log2Matcher.assertStatus(equals: "warn")
        log2Matcher.assertMessage(equals: "log message 2")
    }
}
