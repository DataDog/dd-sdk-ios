import Foundation

/// `LogOutput` which saves logs to file.
internal struct LogFileOutput: LogOutput {
    let logBuilder: LogBuilder
    let fileWriter: FileWriter

    func writeLogWith(level: LogLevel, message: @autoclosure () -> String, attributes: [String: EncodableValue]) {
        let log = logBuilder.createLogWith(level: level, message: message(), attributes: attributes)
        fileWriter.write(value: log)
    }
}
