/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
        let queue = DispatchQueue(label: "com.datadohq.testItWritesCurrentDateToLogs")
        let output = LogFileOutput(
            logBuilder: .mockAny(),
            fileWriter: FileWriter(
                dataFormat: LoggingFeature.Storage.dataFormat,
                orchestrator: FilesOrchestrator(
                    directory: temporaryDirectory,
                    performance: PerformancePreset.combining(
                        storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                        uploadPerformance: .noOp
                    ),
                    dateProvider: fileCreationDateProvider
                ),
                queue: queue
            )
        )

        output.writeLogWith(level: .info, message: "log message 1", date: .mockAny(), attributes: .mockAny(), tags: [])
        queue.sync {} // wait on writter queue

        fileCreationDateProvider.advance(bySeconds: 1)

        output.writeLogWith(level: .info, message: "log message 2", date: .mockAny(), attributes: .mockAny(), tags: [])
        queue.sync {} // wait on writter queue

        let log1FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC())
        let log1Data = try temporaryDirectory.file(named: log1FileName).read()
        let log1Matcher = try LogMatcher.fromJSONObjectData(log1Data)
        log1Matcher.assertMessage(equals: "log message 1")

        let log2FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        let log2Data = try temporaryDirectory.file(named: log2FileName).read()
        let log2Matcher = try LogMatcher.fromJSONObjectData(log2Data)
        log2Matcher.assertMessage(equals: "log message 2")
    }
}
