import XCTest
@testable import Datadog

class WritableFileTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItCreatesNewEmptyFile() throws {
        let file = try WritableFile(newFileInDirectory: temporaryDirectory, createdAt: .mockDecember15th2019At10AMUTC())

        XCTAssertEqual(file.fileURL.lastPathComponent, fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC()))
        XCTAssertEqual(file.creationDate, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(file.initialSize, 0)
    }

    func testWhenFileCannotBeCreated_itThrows() {
        let readonlyDirectory = obtainUniqueTemporaryDirectory()
        readonlyDirectory.create(attributes: [.appendOnly: true])
        defer {
            readonlyDirectory.set(attributes: [.appendOnly: false])
            readonlyDirectory.delete()
        }
        XCTAssertThrowsError(try WritableFile(newFileInDirectory: readonlyDirectory, createdAt: .mockAny())) { error in
            XCTAssertTrue(error is InternalError)
        }
    }

    func testItOpensExistingFile() throws {
        let file = try WritableFile(newFileInDirectory: temporaryDirectory, createdAt: .mockDecember15th2019At10AMUTC())
        let chunk: Data = .mockRepeating(byte: 0x41, times: 10) // 10x uppercase "A"
        try file.append { write in write(chunk) }

        let existingFile = try WritableFile(existingFileFromURL: file.fileURL)
        XCTAssertEqual(existingFile.fileURL.lastPathComponent, fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC()))
        XCTAssertEqual(existingFile.creationDate, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(existingFile.initialSize, 10)
    }

    func testWhenFileCannotBeOpened_itThrows() {
        let notExistingFileURL = temporaryDirectory.urlFor(fileNamed: "123")
        XCTAssertThrowsError(try WritableFile(existingFileFromURL: notExistingFileURL))
    }

    func testItAppendsDataInFile() throws {
        let file = try WritableFile(newFileInDirectory: temporaryDirectory, createdAt: .mockDecember15th2019At10AMUTC())
        let chunkA: Data = .mockRepeating(byte: 0x41, times: 10) // 10x uppercase "A"
        let chunkB: Data = .mockRepeating(byte: 0x42, times: 10) // 10x uppercase "B"

        try file.append { write in
            write(chunkA)
        }

        XCTAssertEqual(try temporaryDirectory.sizeOfFile(named: file.fileURL.lastPathComponent), 10)
        XCTAssertEqual(
            temporaryDirectory.contentsOfFile(fileName: file.fileURL.lastPathComponent),
            Data([0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41])
        )

        try file.append { write in
            write(chunkB)
            write(chunkA)
        }

        XCTAssertEqual(try temporaryDirectory.sizeOfFile(named: file.fileURL.lastPathComponent), 30)
        XCTAssertEqual(
            temporaryDirectory.contentsOfFile(fileName: file.fileURL.lastPathComponent),
            Data(
                [
                0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
                0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                ]
            )
        )
    }

    func testWhenDataCannotBeWritten_itThrows() throws {
        let file = try WritableFile(newFileInDirectory: temporaryDirectory, createdAt: .mockDecember15th2019At10AMUTC())
        try temporaryDirectory.deleteFile(named: file.fileURL.lastPathComponent)

        XCTAssertThrowsError(try file.append { write in write(.mock(ofSize: 1)) })
    }

    func testWhenFileWasDeletedWhileWritting_itDoesNotCrash() throws {
        let file = try WritableFile(newFileInDirectory: temporaryDirectory, createdAt: .mockDecember15th2019At10AMUTC())
        try file.append { write in
            write(.mock(ofSize: 10))
            try! temporaryDirectory.deleteFile(named: file.fileURL.lastPathComponent)
            write(.mock(ofSize: 10))
        }
    }
}
