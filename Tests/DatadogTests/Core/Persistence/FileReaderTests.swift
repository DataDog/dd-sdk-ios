import XCTest
@testable import Datadog

class FileReaderTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-read", target: .global(qos: .utility))
    private let dateProvider = SystemDateProvider()

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
            orchestrator: .mockReadAllFiles(in: temporaryDirectory, using: dateProvider),
            queue: queue
        )
        _ = try temporaryDirectory
            .createFile(named: .mockAnyFileName())
            .append { write in write("ABCD".utf8Data) }

        let batch = reader.readNextBatch()

        XCTAssertEqual(batch?.data, "[ABCD]".utf8Data)
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
        let file1 = try temporaryDirectory.createFile(named: dateProvider.minutesAgo(3).toFileName)
        let file2 = try temporaryDirectory.createFile(named: dateProvider.minutesAgo(2).toFileName)
        let file3 = try temporaryDirectory.createFile(named: dateProvider.minutesAgo(1).toFileName)
        try file1.append { write in write("1".utf8Data) }
        try file2.append { write in write("2".utf8Data) }
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
