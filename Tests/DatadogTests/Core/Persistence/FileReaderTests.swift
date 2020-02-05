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
        _ = try temporaryDirectory
            .createFile(named: .mockAnyFileName())
            .append { write in write("ABCD".utf8Data) }

        let batch = reader.readNextBatch()

        XCTAssertEqual(batch?.data, "[ABCD]".utf8Data)
    }

    func testItMarksBatchesAsRead() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
                readConditions: LogsPersistenceStrategy.defaultReadConditions,
                dateProvider: dateProvider
            ),
            queue: queue
        )
        let file1 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
        try file1.append { write in write("1".utf8Data) }

        let file2 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
        try file2.append { write in write("2".utf8Data) }

        let file3 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
        try file3.append { write in write("3".utf8Data) }

        var batch: Batch
        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data, "[1]".utf8Data)
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data, "[2]".utf8Data)
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.data, "[3]".utf8Data)
        reader.markBatchAsRead(batch)

        XCTAssertNil(reader.readNextBatch())
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }
}
