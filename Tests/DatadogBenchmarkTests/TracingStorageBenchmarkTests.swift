/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingStorageBenchmarkTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var queue: DispatchQueue!
    private var directory: Directory!
    private var writer: FileWriter!
    private var reader: FileReader!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.queue = DispatchQueue(label: "com.datadoghq.benchmark-traces-io", target: .global(qos: .utility))
        self.directory = try Directory(withSubdirectoryPath: "tracing-benchmark")

        let storage = TracingFeature.Storage(
            directory: directory,
            performance: .default,
            dateProvider: SystemDateProvider(),
            readWriteQueue: queue
        )

        self.writer = storage.writer
        self.reader = storage.reader

        XCTAssertTrue(try directory.files().count == 0)
    }

    override func tearDown() {
        self.directory.delete()
        queue = nil
        directory = nil
        writer = nil
        reader = nil
        super.tearDown()
    }

    func testWrittingSpansOnDisc() throws {
        let log = createRandomizedSpan()

        measure {
            writer.write(value: log)
            queue.sync {} // wait to complete async write
        }
    }

    func testReadingSpansFromDisc() throws {
        while try directory.files().count < 10 { // `measureMetrics {}` is fired 10 times so 10 batch files are required
            writer.write(value: createRandomizedSpan())
            queue.sync {} // wait to complete async write
        }

        // Wait enough time for `reader` to accept the youngest batch file
        Thread.sleep(forTimeInterval: PerformancePreset.default.minFileAgeForRead + 0.1)

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

    private func createRandomizedSpan() -> Span {
        let tracingUUIDGenerator = DefaultTracingUUIDGenerator()
        return Span(
            traceID: tracingUUIDGenerator.generateUnique(),
            spanID: tracingUUIDGenerator.generateUnique(),
            parentID: nil,
            operationName: "span \(Int.random(in: 0..<100))",
            serviceName: "service-name",
            resource: "benchmarks",
            startTime: Date(),
            duration: Double.random(in: 0.0..<1.0),
            isError: false,
            tracerVersion: "0.0.0",
            applicationVersion: "0.0.0",
            networkConnectionInfo: NetworkConnectionInfo(
                reachability: .yes,
                availableInterfaces: [.cellular],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: false,
                isConstrained: false
            ),
            mobileCarrierInfo: nil,
            userInfo: .init(id: "abc-123", name: "foo", email: "foo@bar.com"),
            tags: [
                "tag": JSONStringEncodableValue("value", encodedUsing: JSONEncoder())
            ]
        )
    }
}
