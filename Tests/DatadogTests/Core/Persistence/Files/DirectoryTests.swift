import XCTest
@testable import Datadog

class DirectoryTests: XCTestCase {
    private let uniqueSubdirectoryName = UUID().uuidString

    func testGivenSubdirectoryName_itCreatesIt() throws {
        let directory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName)
        defer { directory.delete() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
    }

    func testGivenSubdirectoryPath_itCreatesIt() throws {
        let path = uniqueSubdirectoryName + "/subdirectory/another-subdirectory"
        let directory = try Directory(withSubdirectoryPath: path)
        defer { directory.delete() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
    }

    func testItCreatesFileWithinDirectory() throws {
        let path = uniqueSubdirectoryName + "/subdirectory/another-subdirectory"
        let directory = try Directory(withSubdirectoryPath: path)
        defer { directory.delete() }

        _ = try directory.createFile(named: "abcd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("abcd").path))
    }

    func testWhenDirectoryExists_itDoesNothing() throws {
        let path = uniqueSubdirectoryName + "/subdirectory/another-subdirectory"
        let originalDirectory = try Directory(withSubdirectoryPath: path)
        defer { originalDirectory.delete() }
        _ = try originalDirectory.createFile(named: "abcd")

        // Try again when directory exists
        let retrievedDirectory = try Directory(withSubdirectoryPath: path)

        XCTAssertEqual(retrievedDirectory.url, originalDirectory.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retrievedDirectory.url.appendingPathComponent("abcd").path))
    }
}
