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

        output.writeLogWith(level: .info, message: "log message", attributes: [:])

        queue.sync {} // wait on writter queue

        let fileName = fileNameFrom(fileCreationDate: dateProvider.currentFileCreationDate())
        guard let fileData = temporaryDirectory.contentsOfFile(fileName: fileName) else {
            XCTFail()
            return
        }

        assertThat(jsonObjectData: fileData, matchesValue: "log message", onKeyPath: "message")
    }
}
