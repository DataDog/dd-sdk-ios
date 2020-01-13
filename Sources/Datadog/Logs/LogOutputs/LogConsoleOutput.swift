import Foundation

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
