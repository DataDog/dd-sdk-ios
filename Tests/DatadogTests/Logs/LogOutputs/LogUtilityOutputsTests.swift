import XCTest
@testable import Datadog

class CombinedLogOutputTests: XCTestCase {
    /// Basic `LogOutput` mock only recording received logs.
    class LogOutputMock: LogOutput {
        var logWritten: Log?
        init() {}
        func write(log: Log) { logWritten = log }
    }

    private let log: Log = .mockRandom()

    func testCombinedLogOutput_writesLogToAllCombinedOutputs() {
        let output1 = LogOutputMock()
        let output2 = LogOutputMock()
        let output3 = LogOutputMock()

        let combinedOutput = CombinedLogOutput(combine: [output1, output2, output3])
        combinedOutput.write(log: log)

        XCTAssertEqual(output1.logWritten, log)
        XCTAssertEqual(output2.logWritten, log)
        XCTAssertEqual(output3.logWritten, log)
    }

    func testConditionalLogOutput_writesLogToCombinedOutputOnlyIfConditionIsMet() {
        let output1 = LogOutputMock()
        let conditionalOutput1 = ConditionalLogOutput(conditionedOutput: output1) { _ in true }

        conditionalOutput1.write(log: log)
        XCTAssertEqual(output1.logWritten, log)

        let output2 = LogOutputMock()
        let conditionalOutput2 = ConditionalLogOutput(conditionedOutput: output2) { _ in false }

        conditionalOutput2.write(log: log)
        XCTAssertNil(output2.logWritten)
    }
}
