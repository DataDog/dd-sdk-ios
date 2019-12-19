import Foundation

public class Logger {
    private let uploader: LogsUploader

    // TODO: RUMM-126 Make logger public `init()` not depend on `Datadog` object
    public convenience init(configuration: Datadog) {
        self.init(
            uploader: LogsUploader(
                configuration: configuration,
                httpClient: HTTPClient()
            )
        )
    }
    
    internal init(uploader: LogsUploader) {
        self.uploader = uploader
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
        let log = Log(date: Date(), status: status, message: message(), service: "ios-sdk-test-service")
        do {
            try uploader.upload(logs: [log]) { (status) in
                print("ℹ️ logs delivery status: \(status)")
            }
        } catch {
            print("🔥 logs not delivered due to: \(error)")
        }
    }
}
