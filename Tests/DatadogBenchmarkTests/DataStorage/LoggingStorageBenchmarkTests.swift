/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggingStorageBenchmarkTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var queue: DispatchQueue!
    private var directory: Directory!
    private var writer: Writer!
    private var reader: Reader!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.directory = try Directory(withSubdirectoryPath: "logging-benchmark")

        let storage = LoggingFeature.createStorage(
            directories: FeatureDirectories(
                unauthorized: obtainUniqueTemporaryDirectory(),
                authorized: directory
            ),
            commonDependencies: .mockAny()
        )
        self.writer = storage.writer
        self.reader = storage.reader
        self.queue = (storage.writer as! ConsentAwareDataWriter).queue

        XCTAssertTrue(try directory.files().isEmpty)
    }

    override func tearDown() {
        self.directory.delete()
        queue = nil
        directory = nil
        writer = nil
        reader = nil
        super.tearDown()
    }

    func testWritingLogsOnDisc() throws {
        let log = createRandomizedLog()

        measure {
            writer.write(value: log)
            queue.sync {} // wait to complete async write
        }
    }

    func testReadingLogsFromDisc() throws {
        while try directory.files().count < 10 { // `measureMetrics {}` is fired 10 times so 10 batch files are required
            writer.write(value: createRandomizedLog())
            queue.sync {} // wait to complete async write
        }

        // Wait enough time for `reader` to accept the youngest batch file
        Thread.sleep(forTimeInterval: PerformancePreset.benchmarksPreset.minFileAgeForRead + 0.1)

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            self.startMeasuring()
            let batch = reader.readNextBatch()
            self.stopMeasuring()

            XCTAssertNotNil(batch, "Not enough batch files were created for this benchmark.")

            if let batch = batch {
                reader.markBatchAsRead(batch)
            }
        }
    }

    // MARK: - Helpers

    private func createRandomizedLog() -> LogEvent {
        return LogEvent(
            date: Date(),
            status: .info,
            message: "message \(Int.random(in: 0..<100))",
            error: .init(
                kind: nil,
                message: "description",
                stack: nil
            ),
            serviceName: "service-name",
            environment: "benchmarks",
            loggerName: "logger-name",
            loggerVersion: "0.0.0",
            threadName: "main",
            applicationVersion: "0.0.0",
            userInfo: .init(id: "abc-123", name: "foo", email: "foo@bar.com", extraInfo: ["str": "value", "int": 11_235, "bool": true]),
            networkConnectionInfo: .init(
                reachability: .yes,
                availableInterfaces: [.cellular],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: false,
                isConstrained: false
            ),
            mobileCarrierInfo: nil,
            attributes: LogEvent.Attributes(
                userAttributes: ["user.attribute": "value"],
                internalAttributes: ["internal.attribute": "value"]
            ),
            tags: ["tag:value"]
        )
    }
}
