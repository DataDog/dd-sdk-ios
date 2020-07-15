/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `LogOutput` which does nothing.
internal struct NoOpLogOutput: LogOutput {
    func writeLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>) {}
}

/// Combines one or more `LogOutputs` into one.
internal struct CombinedLogOutput: LogOutput {
    let combinedOutputs: [LogOutput]

    init(combine outputs: [LogOutput]) {
        self.combinedOutputs = outputs
    }

    func writeLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>) {
        combinedOutputs.forEach { $0.writeLogWith(level: level, message: message, date: date, attributes: attributes, tags: tags) }
    }
}

internal struct ConditionalLogOutput: LogOutput {
    let conditionedOutput: LogOutput
    let condition: (LogLevel) -> Bool

    func writeLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>) {
        if condition(level) {
            conditionedOutput.writeLogWith(level: level, message: message, date: date, attributes: attributes, tags: tags)
        }
    }
}
