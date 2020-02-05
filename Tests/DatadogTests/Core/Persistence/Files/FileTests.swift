import XCTest
@testable import Datadog

class FileTests: XCTestCase {
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItAppendsDataToFile() throws {
        let file = try temporaryDirectory.createFile(named: "file")

        try file.append { write in
            write(Data([0x41, 0x41, 0x41, 0x41, 0x41])) // 5 bytes
        }

        XCTAssertEqual(
            try Data(contentsOf: file.url),
            Data([0x41, 0x41, 0x41, 0x41, 0x41])
        )

        try file.append { write in
            write(Data([0x42, 0x42, 0x42, 0x42, 0x42])) // 5 bytes
            write(Data([0x41, 0x41, 0x41, 0x41, 0x41])) // 5 bytes
        }

        XCTAssertEqual(
            try Data(contentsOf: file.url),
            Data(
                [
                0x41, 0x41, 0x41, 0x41, 0x41,
                0x42, 0x42, 0x42, 0x42, 0x42,
                0x41, 0x41, 0x41, 0x41, 0x41,
                ]
            )
        )
    }

    func testItReadsDataFromFile() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        try file.append { write in write("Hello 👋".utf8Data) }

        XCTAssertEqual(try file.read().utf8String, "Hello 👋")
    }

    func tetsItDeletesFile() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        XCTAssertTrue(fileManager.fileExists(atPath: file.url.path))

        try file.delete()

        XCTAssertFalse(fileManager.fileExists(atPath: file.url.path))
    }

    func testItReturnsFileSize() throws {
        let file = try temporaryDirectory.createFile(named: "file")

        try file.append { write in write(.mock(ofSize: 5)) }
        XCTAssertEqual(try file.size(), 5)

        try file.append { write in write(.mock(ofSize: 10)) }
        XCTAssertEqual(try file.size(), 15)
    }
}
