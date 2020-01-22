import Foundation

/// `LogOutput` which does nothing.
internal struct NoOpLogOutput: LogOutput {
    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable]) {}
}

/// Combines one or more `LogOutputs` into one.
internal struct CombinedLogOutput: LogOutput {
    let combinedOutputs: [LogOutput]

    init(combine outputs: [LogOutput]) {
        self.combinedOutputs = outputs
    }

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable]) {
        combinedOutputs.forEach { $0.writeLogWith(level: level, message: message, attributes: attributes) }
    }
}

internal struct ConditionalLogOutput: LogOutput {
    let conditionedOutput: LogOutput
    let condition: (LogLevel) -> Bool

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable]) {
        if condition(level) {
            conditionedOutput.writeLogWith(level: level, message: message, attributes: attributes)
        }
    }
}
