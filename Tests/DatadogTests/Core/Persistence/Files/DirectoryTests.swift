import XCTest
@testable import Datadog

class DirectoryTests: XCTestCase {
    private let uniqueSubdirectoryName = UUID().uuidString

    func testItCreatesWorkingDirectoryIfNotExists() throws {
        let directory = Directory(url: try createWorkingDirectoryIfNotExists(subdirectory: uniqueSubdirectoryName))
        defer { directory.delete() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
    }

    func testItCreatesFileWithinDirectory() throws {
        let directory = Directory(url: try createWorkingDirectoryIfNotExists(subdirectory: uniqueSubdirectoryName))
        defer { directory.delete() }

        _ = try directory.createFile(named: "abcd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("abcd").path))
    }
}
