import Foundation

/// Datadog SDK configuration object.
public class Datadog {
    static var instance: Datadog?

    // MARK: - Initialization

    public static func initialize(endpointURL: String, clientToken: String) {
        do { try initializeOrThrow(endpointURL: endpointURL, clientToken: clientToken)
        } catch { fatalError("Programmer error - \(error)") }
    }

    static func initializeOrThrow(endpointURL: String, clientToken: String) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "Datadog SDK is already initialized.")
        }
        self.instance = Datadog(
            logsUploader: LogsUploader(validURL: try .init(endpointURL: endpointURL, clientToken: clientToken))
        )
    }

    // MARK: - Deinitialization

    public static func stop() {
        do { try stopOrThrow()
        } catch { fatalError("Programmer error - \(error)") }
    }

    static func stopOrThrow() throws {
        guard Datadog.instance != nil else {
            throw ProgrammerError(description: "Attempted to stop SDK before it was initialized.")
        }
        Datadog.instance = nil
    }

    // MARK: - Internal

    // TODO: RUMM-109 Make `logsUploader` dependency private when logs are uploaded from files
    let logsUploader: LogsUploader

    init(logsUploader: LogsUploader) {
        self.logsUploader = logsUploader
    }
}

/// An exception thrown due to programmer error when calling SDK public API.
/// It will stop current process execution and crash the app 💥.
/// When thrown, check if configuration passed to `Datadog.initialize(...)` is correct
/// and if you not call any other SDK methods before it returns.
internal struct ProgrammerError: Error, CustomStringConvertible {
    let description: String
}
