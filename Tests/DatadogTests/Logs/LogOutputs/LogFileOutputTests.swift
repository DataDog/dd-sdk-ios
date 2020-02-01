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
        let dateProvider = DateProviderMock()
        dateProvider.currentFileCreationDates = [.mockDecember15th2019At10AMUTC()]
        let queue = DispatchQueue(label: "any")

        let output = LogFileOutput(
            logBuilder: .mockUsing(date: .mockAny()),
            fileWriter: .mockWrittingToSingleFile(
                in: temporaryDirectory,
                on: queue,
                using: dateProvider
            )
        )

        output.writeLogWith(level: .info, message: "log message", attributes: [:], tags: [])

        queue.sync {} // wait on writter queue

        let file = try temporaryDirectory.file(named: dateProvider.currentFileCreationDate().toFileName)
        let fileData = try file.read()

        assertThat(jsonObjectData: fileData, matchesValue: "log message", onKeyPath: "message")
    }
}
