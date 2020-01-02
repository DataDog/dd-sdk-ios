import XCTest
@testable import Datadog

class FileWriterTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-write", target: .global(qos: .utility))

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
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
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
            try temporaryDirectory.textEncodedDataFromFirstFile(),
            #"{"key1":"value1"},{"key2":"value3"},{"key3":"value3"}"#
        )
    }

    func testItDropsData_whenItExceedsMaxWriteSize() throws {
        let expectation1 = self.expectation(description: "first write completed")
        let expectation2 = self.expectation(description: "second write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue,
            maxWriteSize: 17 // 17 bytes is enough to write {"key1":"value1"} JSON
        )

        writer.write(value: ["key1": "value1"]) // will be written

        waitForWritesCompletion(on: queue, thenFulfill: expectation1)
        wait(for: [expectation1], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.textEncodedDataFromFirstFile(), #"{"key1":"value1"}"#)

        writer.write(value: ["key2": "value3 that makes it exceed 17 bytes"]) // will be dropped

        waitForWritesCompletion(on: queue, thenFulfill: expectation2)
        wait(for: [expectation2], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.textEncodedDataFromFirstFile(), #"{"key1":"value1"}"#) // same content as previously
    }

    private func waitForWritesCompletion(on queue: DispatchQueue, thenFulfill expectation: XCTestExpectation) {
        queue.async { expectation.fulfill() }
    }
}
