/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct CombinedLogOutput: LogOutput {
    let combinedOutputs: [LogOutput]

    init(combine outputs: [LogOutput]) {
        self.combinedOutputs = outputs
    }

    func write(log: Log) {
        combinedOutputs.forEach { $0.write(log: log) }
    }
}

/// Sends the log to `conditionedOutput` only if the `condition` is met.
internal struct ConditionalLogOutput: LogOutput {
    let conditionedOutput: LogOutput
    let condition: (Log) -> Bool

    func write(log: Log) {
        if condition(log) {
            conditionedOutput.write(log: log)
        }
    }
}
