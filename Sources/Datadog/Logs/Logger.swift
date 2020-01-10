import Foundation

public class Logger {
    let serviceName: String

    init(serviceName: String) {
        self.serviceName = serviceName
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
        // TODO: RUMM-128 Evaluate `message()` only if "datadog" or "console" output is enabled
        let log = Log(date: Date(), status: status, message: message(), service: serviceName)
        do {
            _ = log
            // TODO: RUMM-109 Write log to file
        } catch {
            print("🔥 logs not delivered due to: \(error)")
        }
    }

    // MARK: - Logger.Builder

    public static var builder: Builder {
        return Builder()
    }

    public class Builder {
        private var serviceName: String = "ios"

        public func set(serviceName: String) -> Builder {
            self.serviceName = serviceName
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
                serviceName: serviceName
            )
        }
    }
}
