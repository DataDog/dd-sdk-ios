/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import DatadogRUM

@testable import DatadogCore

class RUMStorageBenchmarkTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var queue: DispatchQueue!
    private var directory: Directory!
    private var writer: Writer!
    private var reader: Reader!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.directory = try Directory(withSubdirectoryPath: "rum-benchmark")
        self.queue = DispatchQueue(label: "rum-benchmark")

        let storage = FeatureStorage(
            featureName: "rum",
            queue: queue,
            directories: .init(
                unauthorized: directory,
                authorized: directory
            ),
            dateProvider: SystemDateProvider(),
            performance: .benchmarksPreset,
            encryption: nil
        )

        self.writer = storage.writer(for: .granted, forceNewBatch: false)
        self.reader = storage.reader

        XCTAssertTrue(try directory.files().isEmpty)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory.url)
        queue = nil
        directory = nil
        writer = nil
        reader = nil
        super.tearDown()
    }

    func testWritingRUMEventsOnDisc() throws {
        let event: RUMViewEvent = .mockRandom()

        measure {
            writer.write(value: event)
            queue.sync {} // wait to complete async write
        }
    }

    func testReadingRUMEventsFromDisc() throws {
        while try directory.files().count < 10 { // `measureMetrics {}` is fired 10 times so 10 batch files are required
            writer.write(value: RUMViewEvent.mockRandom())
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
                reader.markBatchAsRead(batch, reason: .flushed)
            }
        }
    }
}
