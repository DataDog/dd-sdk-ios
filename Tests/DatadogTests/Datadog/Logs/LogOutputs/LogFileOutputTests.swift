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
        let queue = DispatchQueue(label: "any")
        let output = LogFileOutput(
            logBuilder: .mockWith(date: .mockAny()),
            fileWriter: FileWriter(
                dataFormat: LoggingFeature.Storage.dataFormat,
                orchestrator: FilesOrchestrator(
                    directory: temporaryDirectory,
                    performance: PerformancePreset.default,
                    dateProvider: SystemDateProvider()
                ),
                queue: queue
            )
        )

        output.writeLogWith(level: .info, message: "log message", attributes: [:], tags: [])

        queue.sync {} // wait on writter queue

        let fileData = try temporaryDirectory.files()[0].read()
        try LogMatcher.fromJSONObjectData(fileData).assertMessage(equals: "log message")
    }
}
