import Foundation

/// Type writting logs to some destination.
internal protocol LogOutput {
    func write(log: Log)
}

// MARK: - Concrete outputs

/// `LogOutput` which saves logs to file.
internal struct LogFileOutput: LogOutput {
    let fileWriter: FileWriter

    func write(log: Log) {
        fileWriter.write(value: log)
    }
}

/// `LogOutput` which prints logs to console.
internal struct LogConsoleOutput: LogOutput {
    private let printingFunction: (String) -> Void

    init(printingFunction: @escaping (String) -> Void = { print($0) }) {
        self.printingFunction = printingFunction
    }

    func write(log: Log) {
        printingFunction("🐶 \(log)")
    }
}

/// `LogOutput` which does nothing.
internal struct NoOpLogOutput: LogOutput {
    func write(log: Log) {}
}

// MARK: - Outputs arithmetics

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
