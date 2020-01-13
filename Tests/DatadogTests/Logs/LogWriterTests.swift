import XCTest
@testable import Datadog

class LogWriterTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-write", target: .global(qos: .utility))

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
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [.mockDecember15th2019At10AMUTC()]
        let writer = LogWriter(
            fileWriter: .mockWrittingToSingleFile(in: temporaryDirectory, on: queue, using: dateProvider),
            serviceName: "test-service-name",
            dateProvider: dateProvider
        )

        writer.writeLog(status: .mockRandom(), message: "some message")

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
