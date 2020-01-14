import Foundation

/// Saves logs to file.
internal final class LogWriter {
    /// Writes serialized log data to file.
    private let fileWriter: FileWriter
    /// Service name sent in logs.
    private let serviceName: String
    /// Provides date for logs.
    private let dateProvider: DateProvider

    init(fileWriter: FileWriter, serviceName: String, dateProvider: DateProvider) {
        self.fileWriter = fileWriter
        self.serviceName = serviceName
        self.dateProvider = dateProvider
    }

    func writeLog(status: Log.Status, message: @autoclosure () -> String) {
        let log = createLog(status: status, message: message())
        fileWriter.write(value: log)
    }

    private func createLog(status: Log.Status, message: @autoclosure () -> String) -> Log {
        return Log(
            date: dateProvider.currentDate(),
            status: status,
            message: message(),
            service: serviceName
        )
    }
}
