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

    /// Logs INFO message.
    ///
    /// - Parameter message: the message
    public func info(_ message: String) {
        log(status: "INFO", message: message)
    }

    private func log(status: String, message: String) {
        let log = Log(date: Date(), status: status, message: message, service: "ios-sdk-test-service")
        do {
            try uploader.upload(logs: [log]) { (status) in
                print("ℹ️ logs delivery status: \(status)")
            }
        } catch {
            print("🔥 logs not delivered due to: \(error)")
        }
    }
}
