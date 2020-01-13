import Foundation

/// `LogOutput` which saves logs to file.
internal struct LogFileOutput: LogOutput {
    let fileWriter: FileWriter

    func write(log: Log) {
        fileWriter.write(value: log)
    }
}
