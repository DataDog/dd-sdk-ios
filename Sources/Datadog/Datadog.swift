import Foundation

/// SDK version associated with logs.
/// Should be synced with SDK releases.
internal let sdkVersion = "1.0.0-alpha1"

/// Datadog SDK configuration object.
public class Datadog {
    internal static var instance: Datadog?

    internal let appContext: AppContext
    internal let dateProvider: DateProvider

    // MARK: - Logs

    internal let logsPersistenceStrategy: LogsPersistenceStrategy
    internal let logsUploadStrategy: LogsUploadStrategy

    internal convenience init(appContext: AppContext, endpointURL: String, clientToken: String, dateProvider: DateProvider) throws {
        let logsPersistenceStrategy: LogsPersistenceStrategy = try .defalut(using: dateProvider)
        let logsUploadStrategy: LogsUploadStrategy = try .defalut(
            endpointURL: endpointURL,
            clientToken: clientToken,
            reader: logsPersistenceStrategy.reader
        )
        self.init(
            appContext: appContext,
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider
        )
    }

    internal init(
        appContext: AppContext,
        logsPersistenceStrategy: LogsPersistenceStrategy,
        logsUploadStrategy: LogsUploadStrategy,
        dateProvider: DateProvider
    ) {
        self.appContext = appContext
        self.dateProvider = dateProvider
        self.logsPersistenceStrategy = logsPersistenceStrategy
        self.logsUploadStrategy = logsUploadStrategy
    }
}

extension Datadog {
    /// Context providing information about the app.
    public struct AppContext {
        internal let bundleIdentifier: String?
        internal let bundleVersion: String?
        internal let bundleShortVersion: String?

        public init(mainBundle: Bundle = Bundle.main) {
            self.init(
                bundleIdentifier: mainBundle.bundleIdentifier,
                bundleVersion: mainBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                bundleShortVersion: mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            )
        }

        internal init(bundleIdentifier: String?, bundleVersion: String?, bundleShortVersion: String?) {
            self.bundleIdentifier = bundleIdentifier
            self.bundleVersion = bundleVersion
            self.bundleShortVersion = bundleShortVersion
        }
    }

    // MARK: - Initialization

    public static func initialize(appContext: AppContext, endpointURL: String, clientToken: String) {
        do { try initializeOrThrow(appContext: appContext, endpointURL: endpointURL, clientToken: clientToken)
        } catch {
            userLogger.critical("\(error)")
            fatalError("Programmer error - \(error)")  // crash
        }
    }

    static func initializeOrThrow(appContext: AppContext, endpointURL: String, clientToken: String) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "SDK is already initialized.")
        }
        self.instance = try Datadog(
            appContext: appContext,
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

/// Convenience typealias.
internal typealias AppContext = Datadog.AppContext

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
