import XCTest
@testable import Datadog

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
