/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

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

        let storage = RUMFeature.createStorage(
            directories: FeatureDirectories(
                unauthorized: obtainUniqueTemporaryDirectory(),
                authorized: directory
            ),
            commonDependencies: .mockAny()
        )
        self.writer = storage.writer
        self.reader = storage.reader
        self.queue = (storage.writer as! ConsentAwareDataWriter).readWriteQueue

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

    func testWrittingRUMEventsOnDisc() throws {
        let event = createRandomizedRUMEvent()

        measure {
            writer.write(value: event)
            queue.sync {} // wait to complete async write
        }
    }

    func testReadingRUMEventsFromDisc() throws {
        while try directory.files().count < 10 { // `measureMetrics {}` is fired 10 times so 10 batch files are required
            writer.write(value: createRandomizedRUMEvent())
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

    private func createRandomizedRUMEvent() -> RUMEvent<RUMViewEvent> {
        return RUMEvent(
            model: RUMViewEvent(
                dd: .init(documentVersion: .mockAny()),
                application: .init(id: UUID().uuidString),
                connectivity: nil,
                date: Int64.random(in: Int64.min..<Int64.max),
                service: .mockRandom(length: 20),
                session: .init(hasReplay: nil, id: UUID().uuidString, type: .user),
                usr: .init(
                    email: .mockRandom(length: 10),
                    id: .mockRandom(length: 10),
                    name: .mockRandom(length: 10)
                ),
                view: .init(
                    action: .init(count: .mockAny()),
                    crash: .init(count: .mockAny()),
                    cumulativeLayoutShift: nil,
                    customTimings: .mockAny(),
                    domComplete: nil,
                    domContentLoaded: nil,
                    domInteractive: nil,
                    error: .init(count: .mockAny()),
                    firstContentfulPaint: nil,
                    firstInputDelay: nil,
                    firstInputTime: nil,
                    id: UUID().uuidString,
                    isActive: nil,
                    largestContentfulPaint: nil,
                    loadEvent: nil,
                    loadingTime: .mockAny(),
                    loadingType: nil,
                    longTask: nil,
                    referrer: .mockRandom(length: 10),
                    resource: .init(count: .mockAny()),
                    timeSpent: .mockAny(),
                    url: .mockRandom(length: 30)
                )
            ),
            attributes: ["attribute": "value"],
            userInfoAttributes: ["str": "value", "int": 11_235, "bool": true]
        )
    }
}
