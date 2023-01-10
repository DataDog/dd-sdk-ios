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
                ),
                encryption: nil,
                forceNewFile: false
            )
        )

        let log1: LogEvent = .mockWith(status: .info, message: "log message 1")
        output.write(log: log1)

        fileCreationDateProvider.advance(bySeconds: 1)

        let log2: LogEvent = .mockWith(status: .warn, message: "log message 2")
        output.write(log: log2)

        let log1FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC())
        let log1FileEvents = try temporaryDirectory.file(named: log1FileName).readTLVEvents()
        XCTAssertEqual(log1FileEvents.count, 1)
        let log1Matcher = try LogMatcher.fromJSONObjectData(log1FileEvents[0])
        log1Matcher.assertStatus(equals: "info")
        log1Matcher.assertMessage(equals: "log message 1")

        let log2FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        let log2FileEvents = try temporaryDirectory.file(named: log2FileName).readTLVEvents()
        XCTAssertEqual(log2FileEvents.count, 1)
        let log2Matcher = try LogMatcher.fromJSONObjectData(log2FileEvents[0])
        log2Matcher.assertStatus(equals: "warn")
        log2Matcher.assertMessage(equals: "log message 2")
    }
}
