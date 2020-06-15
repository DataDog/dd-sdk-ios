/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CombinedLogOutputTests: XCTestCase {
    func testCombinedLogOutput_writesLogToAllCombinedOutputs() {
        let output1 = LogOutputMock()
        let output2 = LogOutputMock()
        let output3 = LogOutputMock()

        let combinedOutput = CombinedLogOutput(combine: [output1, output2, output3])
        combinedOutput.writeLogWith(level: .info, message: "info message", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])

        XCTAssertEqual(output1.recordedLog, .init(level: .info, message: "info message", date: .mockDecember15th2019At10AMUTC()))
        XCTAssertEqual(output2.recordedLog, .init(level: .info, message: "info message", date: .mockDecember15th2019At10AMUTC()))
        XCTAssertEqual(output3.recordedLog, .init(level: .info, message: "info message", date: .mockDecember15th2019At10AMUTC()))
    }

    func testConditionalLogOutput_writesLogToCombinedOutputOnlyIfConditionIsMet() {
        let output1 = LogOutputMock()
        let conditionalOutput1 = ConditionalLogOutput(conditionedOutput: output1) { _ in true }

        conditionalOutput1.writeLogWith(level: .info, message: "info message", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])
        XCTAssertEqual(output1.recordedLog, .init(level: .info, message: "info message", date: .mockDecember15th2019At10AMUTC()))

        let output2 = LogOutputMock()
        let conditionalOutput2 = ConditionalLogOutput(conditionedOutput: output2) { _ in false }

        conditionalOutput2.writeLogWith(level: .info, message: "info message", date: .mockAny(), attributes: [:], tags: [])
        XCTAssertNil(output2.recordedLog)
    }
}
