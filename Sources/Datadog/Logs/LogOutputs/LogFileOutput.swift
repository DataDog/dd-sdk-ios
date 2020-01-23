import Foundation

/// `LogOutput` which saves logs to file.
internal struct LogFileOutput: LogOutput {
    let logBuilder: LogBuilder
    let fileWriter: FileWriter

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable]) {
        let log = logBuilder.createLogWith(level: level, message: message, attributes: attributes)
        fileWriter.write(value: log)
    }
}
