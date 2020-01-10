import XCTest
@testable import Datadog

class FileReaderTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-read", target: .global(qos: .utility))

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItReadsSingleBatch() throws {
        let reader = FileReader(
            orchestrator: .mockReadAllFiles(in: temporaryDirectory),
            queue: queue
        )
        let data = "ABCD".data(using: .utf8)!
        _ = temporaryDirectory.createFile(withData: data, fileName: "123")

        let batch = reader.readNextBatch()

        XCTAssertEqual(batch?.data, "[ABCD]".data(using: .utf8)!)
    }

    func testItMarksBatchesAsRead() throws {
        let dateProvider = DateProviderMock()
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
                readConditions: LogsPersistenceStrategy.defaultReadConditions,
                dateProvider: dateProvider
            ),
            queue: queue
        )
        _ = temporaryDirectory.createFile(withData: "1".utf8Data, fileName: dateProvider.minutesAgo(3).toFileName)
        _ = temporaryDirectory.createFile(withData: "2".utf8Data, fileName: dateProvider.minutesAgo(2).toFileName)
        _ = temporaryDirectory.createFile(withData: "3".utf8Data, fileName: dateProvider.minutesAgo(1).toFileName)

        print(dateProvider.currentDate().timeIntervalSinceReferenceDate)
        print(try temporaryDirectory.allFiles())

        var batch: Batch
        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data.utf8String, "[1]")
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data.utf8String, "[2]")
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data.utf8String, "[3]")
        reader.markBatchAsRead(batch)

        XCTAssertNil(reader.readNextBatch())
        XCTAssertEqual(try temporaryDirectory.allFiles().count, 0)
    }
}
