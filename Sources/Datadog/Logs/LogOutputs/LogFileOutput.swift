import Foundation

/// `LogOutput` which saves logs to file.
internal struct LogFileOutput: LogOutput {
    let logBuilder: LogBuilder
    let fileWriter: FileWriter

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable], tags: Set<String>) {
        let log = logBuilder.createLogWith(level: level, message: message, attributes: attributes, tags: tags)
        fileWriter.write(value: log)
    }
}
