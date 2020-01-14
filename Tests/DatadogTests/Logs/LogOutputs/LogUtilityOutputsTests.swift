import XCTest
@testable import Datadog

class CombinedLogOutputTests: XCTestCase {
    /// `LogOutput` recording received logs.
    class LogOutputMock: LogOutput {
        struct RecordedLog: Equatable {
            let level: LogLevel
            let message: String
        }

        var recordedLog: RecordedLog? = nil

        func writeLogWith(level: LogLevel, message: @autoclosure () -> String) {
            recordedLog = RecordedLog(level: level, message: message())
        }
    }

    func testCombinedLogOutput_writesLogToAllCombinedOutputs() {
        let output1 = LogOutputMock()
        let output2 = LogOutputMock()
        let output3 = LogOutputMock()

        let combinedOutput = CombinedLogOutput(combine: [output1, output2, output3])
        combinedOutput.writeLogWith(level: .info, message: "info message")

        XCTAssertEqual(output1.recordedLog, .init(level: .info, message: "info message"))
        XCTAssertEqual(output2.recordedLog, .init(level: .info, message: "info message"))
        XCTAssertEqual(output3.recordedLog, .init(level: .info, message: "info message"))
    }

    func testConditionalLogOutput_writesLogToCombinedOutputOnlyIfConditionIsMet() {
        let output1 = LogOutputMock()
        let conditionalOutput1 = ConditionalLogOutput(conditionedOutput: output1) { _ in true }

        conditionalOutput1.writeLogWith(level: .info, message: "info message")
        XCTAssertEqual(output1.recordedLog, .init(level: .info, message: "info message"))

        let output2 = LogOutputMock()
        let conditionalOutput2 = ConditionalLogOutput(conditionedOutput: output2) { _ in false }

        conditionalOutput2.writeLogWith(level: .info, message: "info message")
        XCTAssertNil(output2.recordedLog)
    }
}
