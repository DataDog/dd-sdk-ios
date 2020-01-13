import Foundation

public class Logger {
    /// Builds `Log` objects.
    let logBuilder: LogBuilder
    /// Writes `Log` objects to output.
    let logOutput: LogOutput

    init(logBuilder: LogBuilder, logOutput: LogOutput) {
        self.logBuilder = logBuilder
        self.logOutput = logOutput
    }

    /// Sends a DEBUG log message.
    /// - Parameter message: the message to be logged
    public func debug(_ message: @autoclosure () -> String) {
        log(status: .debug, message: message())
    }

    /// Sends an INFO log message.
    /// - Parameter message: the message to be logged
    public func info(_ message: @autoclosure () -> String) {
        log(status: .info, message: message())
    }

    /// Sends a NOTICE log message.
    /// - Parameter message: the message to be logged
    public func notice(_ message: @autoclosure () -> String) {
        log(status: .notice, message: message())
    }

    /// Sends a WARN log message.
    /// - Parameter message: the message to be logged
    public func warn(_ message: @autoclosure () -> String) {
        log(status: .warn, message: message())
    }

    /// Sends an ERROR log message.
    /// - Parameter message: the message to be logged
    public func error(_ message: @autoclosure () -> String) {
        log(status: .error, message: message())
    }

    /// Sends a CRITICAL log message.
    /// - Parameter message: the message to be logged
    public func critical(_ message: @autoclosure () -> String) {
        log(status: .critical, message: message())
    }

    private func log(status: Log.Status, message: @autoclosure () -> String) {
        let log = logBuilder.createLogWith(status: status, message: message())
        logOutput.write(log: log)
    }

    // MARK: - Logger.Builder

    public static var builder: Builder {
        return Builder()
    }

    public class Builder {
        private var serviceName: String = "ios"
        private var useFileOutput = true
        private var useConsoleLogFormat: ConsoleLogFormat?

        public func set(serviceName: String) -> Builder {
            self.serviceName = serviceName
            return self
        }

        public func sendLogsToDatadog(_ enabled: Bool) -> Builder {
            self.useFileOutput = enabled
            return self
        }

        public enum ConsoleLogFormat {
            case short
            case shortWith(prefix: String)
            case json
            case jsonWith(prefix: String)
        }

        public func sendLogsToConsole(_ enabled: Bool, using format: ConsoleLogFormat = .short) -> Builder {
            useConsoleLogFormat = enabled ? format : nil
            return self
        }

        public func build() -> Logger {
            do { return try buildOrThrow()
            } catch { fatalError("`Logger` cannot be built: \(error)") }
        }

        internal func buildOrThrow() throws -> Logger {
            guard let datadog = Datadog.instance else {
                throw ProgrammerError(description: "`Datadog.initialize()` must be called prior to `Logger.builder.build()`.")
            }

            return Logger(
                logBuilder: LogBuilder(
                    serviceName: serviceName,
                    dateProvider: datadog.dateProvider
                ),
                logOutput: resolveOutputs(using: datadog)
            )
        }

        private func resolveOutputs(using datadog: Datadog) -> LogOutput {
            switch (useFileOutput, useConsoleLogFormat) {
            case (true, let format?):
                return CombinedLogOutput(
                    combine: [
                        LogFileOutput(fileWriter: datadog.logsPersistenceStrategy.writer),
                        LogConsoleOutput(format: format)
                    ]
                )
            case (true, nil):
                return LogFileOutput(fileWriter: datadog.logsPersistenceStrategy.writer)
            case (false, let format?):
                return LogConsoleOutput(format: format)
            case (false, nil):
                return NoOpLogOutput()
            }
        }
    }
}
