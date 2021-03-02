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
        let output = LogFileOutput(
            fileWriter: FileWriter(
                dataFormat: LoggingFeature.dataFormat,
                orchestrator: FilesOrchestrator(
                    directory: temporaryDirectory,
                    performance: PerformancePreset.combining(
                        storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                        uploadPerformance: .noOp
                    ),
                    dateProvider: fileCreationDateProvider
                )
            ),
            rumErrorsIntegration: nil
        )

        let log1: Log = .mockWith(status: .info, message: "log message 1")
        output.write(log: log1)

        fileCreationDateProvider.advance(bySeconds: 1)

        let log2: Log = .mockWith(status: .warn, message: "log message 2")
        output.write(log: log2)

        let log1FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC())
        let log1Data = try temporaryDirectory.file(named: log1FileName).read()
        let log1Matcher = try LogMatcher.fromJSONObjectData(log1Data)
        log1Matcher.assertStatus(equals: "info")
        log1Matcher.assertMessage(equals: "log message 1")

        let log2FileName = fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        let log2Data = try temporaryDirectory.file(named: log2FileName).read()
        let log2Matcher = try LogMatcher.fromJSONObjectData(log2Data)
        log2Matcher.assertStatus(equals: "warn")
        log2Matcher.assertMessage(equals: "log message 2")
    }
}
