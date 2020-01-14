import Foundation

/// `LogOutput` which does nothing.
internal struct NoOpLogOutput: LogOutput {
    func write(log: Log) {}
}

/// Combines one or more `LogOutputs` into one.
internal struct CombinedLogOutput: LogOutput {
    let combinedOutputs: [LogOutput]

    init(combine outputs: [LogOutput]) {
        self.combinedOutputs = outputs
    }

    func write(log: Log) {
        combinedOutputs.forEach { $0.write(log: log) }
    }
}

internal struct ConditionalLogOutput: LogOutput {
    let conditionedOutput: LogOutput
    let condition: (Log) -> Bool

    func write(log: Log) {
        if condition(log) {
            conditionedOutput.write(log: log)
        }
    }
}
