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
            fileWriter: .mockWrittingToSingleFile(
                in: temporaryDirectory,
                on: queue,
                using: dateProvider
            )
        )

        output.write(log: .mockRandom())

        queue.sync {} // wait on writter queue

        let fileName = fileNameFrom(fileCreationDate: dateProvider.currentFileCreationDate())
        guard let fileData = temporaryDirectory.contentsOfFile(fileName: fileName) else {
            XCTFail()
            return
        }

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(try jsonDecoder.decode(Log.self, from: fileData))
    }
}
