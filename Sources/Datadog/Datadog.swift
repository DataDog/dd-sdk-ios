import Foundation

/// Datadog SDK configuration object.
public class Datadog {
    static var instance: Datadog?

    internal let dateProvider: DateProvider

    // MARK: - Logs

    internal let logsPersistenceStrategy: LogsPersistenceStrategy
    internal let logsUploadStrategy: LogsUploadStrategy

    init(endpointURL: String, clientToken: String, dateProvider: DateProvider) throws {
        self.dateProvider = dateProvider
        self.logsPersistenceStrategy = try .defalut(using: dateProvider)
        self.logsUploadStrategy = try .defalut(
            endpointURL: endpointURL,
            clientToken: clientToken,
            reader: logsPersistenceStrategy.reader
        )
    }
}

extension Datadog {
    // MARK: - Initialization

    public static func initialize(endpointURL: String, clientToken: String) {
        do { try initializeOrThrow(endpointURL: endpointURL, clientToken: clientToken)
        } catch { fatalError("Programmer error - \(error)") }
    }

    static func initializeOrThrow(endpointURL: String, clientToken: String) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "SDK is already initialized.")
        }
        self.instance = try Datadog(
            endpointURL: endpointURL,
            clientToken: clientToken,
            dateProvider: SystemDateProvider()
        )
    }

    // MARK: - Deinitialization

    /// Internal feature made only for tests purpose.
    static func deinitializeOrThrow() throws {
        guard Datadog.instance != nil else {
            throw ProgrammerError(description: "Attempted to stop SDK before it was initialized.")
        }
        Datadog.instance = nil
    }
}

/// An exception thrown due to programmer error when calling SDK public API.
/// It will stop current process execution and crash the app 💥.
/// When thrown, check if configuration passed to `Datadog.initialize(...)` is correct
/// and if you not call any other SDK methods before it returns.
internal struct ProgrammerError: Error, CustomStringConvertible {
    init(description: String) { self.description = "Datadog SDK usage error: \(description)" }
    let description: String
}

/// An exception thrown internally by SDK.
/// It is always handled by SDK and never passed to the user - never causing a crash ⛑.
/// `InternalError` might be thrown due to  SDK internal inconsistency or external issues (e.g.  I/O errors).
internal struct InternalError: Error, CustomStringConvertible {
    let description: String
}
