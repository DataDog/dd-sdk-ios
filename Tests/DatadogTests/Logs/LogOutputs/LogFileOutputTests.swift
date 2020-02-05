import XCTest
@testable import Datadog

class LogFileOutputTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItWritesLogToFileAsJSON() throws {
        let queue = DispatchQueue(label: "any")
        let output = LogFileOutput(
            logBuilder: .mockUsing(date: .mockAny()),
            fileWriter: .mockWrittingToSingleFile(in: temporaryDirectory, on: queue)
        )

        output.writeLogWith(level: .info, message: "log message", attributes: [:], tags: [])

        queue.sync {} // wait on writter queue

        let fileData = try temporaryDirectory.files()[0].read()
        assertThat(jsonObjectData: fileData, matchesValue: "log message", onKeyPath: "message")
    }
}
