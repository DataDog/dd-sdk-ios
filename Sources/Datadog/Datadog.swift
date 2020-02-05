import Foundation

/// Internal version information associated with logs.
/// Should be synced with SDK releases.
internal let sdkVersion = "1.0.0-alpha1"

/// Datadog SDK configuration object.
public class Datadog {
    static var instance: Datadog?

    internal let dateProvider: DateProvider

    // MARK: - Logs

    internal let logsPersistenceStrategy: LogsPersistenceStrategy
    internal let logsUploadStrategy: LogsUploadStrategy

    internal convenience init(endpointURL: String, clientToken: String, dateProvider: DateProvider) throws {
        let logsPersistenceStrategy: LogsPersistenceStrategy = try .defalut(using: dateProvider)
        let logsUploadStrategy: LogsUploadStrategy = try .defalut(
            endpointURL: endpointURL,
            clientToken: clientToken,
            reader: logsPersistenceStrategy.reader
        )
        self.init(
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider
        )
    }

    internal init(
        logsPersistenceStrategy: LogsPersistenceStrategy,
        logsUploadStrategy: LogsUploadStrategy,
        dateProvider: DateProvider
    ) {
        self.dateProvider = dateProvider
        self.logsPersistenceStrategy = logsPersistenceStrategy
        self.logsUploadStrategy = logsUploadStrategy
    }
}

extension Datadog {
    // MARK: - Initialization

    public static func initialize(endpointURL: String, clientToken: String) {
        do { try initializeOrThrow(endpointURL: endpointURL, clientToken: clientToken)
        } catch {
            userLogger.critical("\(error)")
            fatalError("Programmer error - \(error)")  // crash
        }
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

    // MARK: - Global configuration

    /// Verbosity level of Datadog SDK. Can be used for debugging purposes.
    /// If set, internal events occuring inside SDK will be printed to debugger console if their level is equal or greater than `verbosityLevel`.
    /// Default is `nil`.
    public static var verbosityLevel: LogLevel? = nil

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
