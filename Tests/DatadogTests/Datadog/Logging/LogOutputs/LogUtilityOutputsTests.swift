/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CombinedLogOutputTests: XCTestCase {
    func testCombinedLogOutput_writesLogToAllCombinedOutputs() {
        let randomLog: Log = .mockRandom()

        let output1 = LogOutputMock()
        let output2 = LogOutputMock()
        let output3 = LogOutputMock()

        let combinedOutput = CombinedLogOutput(combine: [output1, output2, output3])
        combinedOutput.write(log: randomLog)

        XCTAssertEqual(output1.recordedLog, randomLog)
        XCTAssertEqual(output2.recordedLog, randomLog)
        XCTAssertEqual(output3.recordedLog, randomLog)
    }

    func testConditionalLogOutput_writesLogToConditionedOutputOnlyIfConditionIsMet() {
        let randomLog: Log = .mockRandom()

        let output1 = LogOutputMock()
        let conditionalOutput1 = ConditionalLogOutput(conditionedOutput: output1) { _ in true }

        conditionalOutput1.write(log: randomLog)
        XCTAssertEqual(output1.recordedLog, randomLog)

        let output2 = LogOutputMock()
        let conditionalOutput2 = ConditionalLogOutput(conditionedOutput: output2) { _ in false }

        conditionalOutput2.write(log: randomLog)
        XCTAssertNil(output2.recordedLog)
    }
}
