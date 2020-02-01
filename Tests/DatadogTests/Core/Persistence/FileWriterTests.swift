import XCTest
@testable import Datadog

class FileWriterTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-write", target: .global(qos: .utility))
    private let dateProvider = SystemDateProvider()

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItWritesDataToSingleFile() throws {
        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory, using: dateProvider),
            queue: queue,
            maxWriteSize: .max
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value3"])
        writer.write(value: ["key3": "value3"])

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertEqual(
            try temporaryDirectory.files()[0].read(),
            #"{"key1":"value1"},{"key2":"value3"},{"key3":"value3"}"#.utf8Data
        )
    }

    func testItDropsData_whenItExceedsMaxWriteSize() throws {
        let expectation1 = self.expectation(description: "first write completed")
        let expectation2 = self.expectation(description: "second write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory, using: dateProvider),
            queue: queue,
            maxWriteSize: 17 // 17 bytes is enough to write {"key1":"value1"} JSON
        )

        writer.write(value: ["key1": "value1"]) // will be written

        waitForWritesCompletion(on: queue, thenFulfill: expectation1)
        wait(for: [expectation1], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data)

        writer.write(value: ["key2": "value3 that makes it exceed 17 bytes"]) // will be dropped

        waitForWritesCompletion(on: queue, thenFulfill: expectation2)
        wait(for: [expectation2], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data) // same content as before
    }

    // TODO: RUMM-140 Add performance tests - test this behaviour in more relevant place
    func testItWrites10KLogsInReasonableTime() throws {
        let expectation = self.expectation(description: "10K writes completed")
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
                readConditions: LogsPersistenceStrategy.defaultReadConditions,
                dateProvider: SystemDateProvider()
            ),
            queue: queue,
            maxWriteSize: LogsPersistenceStrategy.Constants.maxLogSize
        )

        for _ in 0..<10_000 {
            let log: Log = .mockRandom()
            writer.write(value: log)
        }

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 20) // 20 seconds is an arbitrary timeout

        XCTAssertGreaterThan(try temporaryDirectory.files().count, 1)
    }

    private func waitForWritesCompletion(on queue: DispatchQueue, thenFulfill expectation: XCTestExpectation) {
        queue.async { expectation.fulfill() }
    }
}
