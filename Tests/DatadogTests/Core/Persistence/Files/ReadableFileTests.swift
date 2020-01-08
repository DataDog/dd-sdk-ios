import XCTest
@testable import Datadog

class ReadableFileTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItOpensExistingFile() throws {
        let fileURL = temporaryDirectory.createFile(withData: .mock(ofSize: 10), createdAt: .mockDecember15th2019At10AMUTC())
        let existingFile = try ReadableFile(existingFileFromURL: fileURL)

        XCTAssertEqual(existingFile.fileURL.lastPathComponent, fileNameFrom(fileCreationDate: .mockDecember15th2019At10AMUTC()))
        XCTAssertEqual(existingFile.creationDate, .mockDecember15th2019At10AMUTC())
    }

    func testWhenFileCannotBeOpened_itThrows() {
        let notExistingFileURL = temporaryDirectory.urlFor(fileNamed: "123")

        XCTAssertThrowsError(try ReadableFile(existingFileFromURL: notExistingFileURL)) { error in
            XCTAssertTrue(error is InternalError)
        }
    }

    func testItReadsDataFromFile() throws {
        let data = "ABCD".data(using: .utf8)!
        let fileURL = temporaryDirectory.createFile(withData: data, createdAt: .mockDecember15th2019At10AMUTC())

        let file = try ReadableFile(existingFileFromURL: fileURL)
        let dataInFile = try file.read()

        XCTAssertEqual(dataInFile, data)
    }

    func testWhenDataCannotBeRead_itThrows() throws {
        let fileURL = temporaryDirectory.createFile(withData: .mock(ofSize: 1), createdAt: .mockDecember15th2019At10AMUTC())
        let file = try ReadableFile(existingFileFromURL: fileURL)
        try temporaryDirectory.deleteFile(named: fileURL.lastPathComponent)

        XCTAssertThrowsError(try file.read())
    }
}
