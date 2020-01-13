import XCTest
@testable import Datadog

class LogFileOutputTests: XCTestCase {
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
        dateProvider.currentFileCreationDates = [.mockDecember15th2019At10AMUTC()]

        let output = LogFileOutput(
            fileWriter: .mockWrittingToSingleFile(in: temporaryDirectory, on: queue, using: dateProvider)
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

class LogConsoleOutputTests: XCTestCase {
    func testItPrintsLogUsingPrintingFunction() {
        var messagePrinted: String = ""

        let output = LogConsoleOutput { message in
            messagePrinted = message
        }

        let log: Log = .mockRandom()
        output.write(log: log)

        XCTAssertTrue(messagePrinted != "")
    }
}

class CombinedLogOutputTests: XCTestCase {
    /// Basic `LogOutput` mock only recording received logs.
    class LogOutputMock: LogOutput {
        var logWritten: Log?
        init() {}
        func write(log: Log) { logWritten = log }
    }

    func testItCombinesMultipleOutputs() {
        let output1 = LogOutputMock()
        let output2 = LogOutputMock()
        let output3 = LogOutputMock()

        let combinedOutput = CombinedLogOutput(combine: [output1, output2, output3])
        let log: Log = .mockRandom()
        combinedOutput.write(log: log)

        XCTAssertEqual(output1.logWritten, log)
        XCTAssertEqual(output2.logWritten, log)
        XCTAssertEqual(output3.logWritten, log)
    }
}
