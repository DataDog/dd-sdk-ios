import Foundation

/// SDK version associated with logs.
/// Should be synced with SDK releases.
internal let sdkVersion = "1.0.0-alpha2"

/// Datadog SDK configuration object.
public class Datadog {
    internal static var instance: Datadog?

    internal let appContext: AppContext
    internal let dateProvider: DateProvider
    internal let userInfoProvider: UserInfoProvider
    internal let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    internal let carrierInfoProvider: CarrierInfoProviderType?

    // MARK: - Logs

    internal let logsPersistenceStrategy: LogsPersistenceStrategy
    internal let logsUploadStrategy: LogsUploadStrategy

    internal convenience init(
        appContext: AppContext,
        endpoint: LogsEndpoint,
        clientToken: String,
        dateProvider: DateProvider,
        userInfoProvider: UserInfoProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType?
    ) throws {
        let logsPersistenceStrategy: LogsPersistenceStrategy = try .defalut(using: dateProvider)
        let logsUploadStrategy: LogsUploadStrategy = try .defalut(
            appContext: appContext,
            endpointURL: endpoint.url,
            clientToken: clientToken,
            reader: logsPersistenceStrategy.reader,
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )
        self.init(
            appContext: appContext,
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }

    internal init(
        appContext: AppContext,
        logsPersistenceStrategy: LogsPersistenceStrategy,
        logsUploadStrategy: LogsUploadStrategy,
        dateProvider: DateProvider,
        userInfoProvider: UserInfoProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType?
    ) {
        self.appContext = appContext
        self.dateProvider = dateProvider
        self.logsPersistenceStrategy = logsPersistenceStrategy
        self.logsUploadStrategy = logsUploadStrategy
        self.userInfoProvider = userInfoProvider
        self.networkConnectionInfoProvider = networkConnectionInfoProvider
        self.carrierInfoProvider = carrierInfoProvider
    }
}

extension Datadog {
    /// Determines server to which logs are sent.
    public enum LogsEndpoint {
        /// US based servers.
        /// Sends logs to [app.datadoghq.com](https://app.datadoghq.com/).
        case us // swiftlint:disable:this identifier_name
        /// Europe based servers.
        /// Sends logs to [app.datadoghq.eu](https://app.datadoghq.eu/).
        case eu // swiftlint:disable:this identifier_name
        /// User-defined server.
        case custom(url: String)

        var url: String {
            switch self {
            case .us: return "https://mobile-http-intake.logs.datadoghq.com/v1/input/"
            case .eu: return "https://mobile-http-intake.logs.datadoghq.eu/v1/input/"
            case let .custom(url: url): return url
            }
        }
    }

    /// Provides information about the app.
    public struct AppContext {
        internal let bundleIdentifier: String?
        internal let bundleVersion: String?
        internal let bundleShortVersion: String?
        internal let executableName: String?
        /// Describes current mobile device if SDK runs on a platform that supports `UIKit`.
        internal let mobileDevice: MobileDevice?

        public init(mainBundle: Bundle = Bundle.main) {
            self.init(
                bundleIdentifier: mainBundle.bundleIdentifier,
                bundleVersion: mainBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                bundleShortVersion: mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                executableName: mainBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                mobileDevice: MobileDevice.current
            )
        }

        internal init(
            bundleIdentifier: String?,
            bundleVersion: String?,
            bundleShortVersion: String?,
            executableName: String?,
            mobileDevice: MobileDevice?
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.bundleVersion = bundleVersion
            self.bundleShortVersion = bundleShortVersion
            self.executableName = executableName
            self.mobileDevice = mobileDevice
        }
    }

    // MARK: - Initialization

    public static func initialize(appContext: AppContext, endpoint: LogsEndpoint, clientToken: String) {
        do { try initializeOrThrow(appContext: appContext, endpoint: endpoint, clientToken: clientToken)
        } catch {
            userLogger.critical("\(error)")
            fatalError("Programmer error - \(error)")  // crash
        }
    }

    static func initializeOrThrow(appContext: AppContext, endpoint: LogsEndpoint, clientToken: String) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "SDK is already initialized.")
        }
        self.instance = try Datadog(
            appContext: appContext,
            endpoint: endpoint,
            clientToken: clientToken,
            dateProvider: SystemDateProvider(),
            userInfoProvider: UserInfoProvider(),
            networkConnectionInfoProvider: NetworkConnectionInfoProvider(),
            carrierInfoProvider: CarrierInfoProvider.getIfAvailable()
        )
    }

    // MARK: - Global configuration

    /// Verbosity level of Datadog SDK. Can be used for debugging purposes.
    /// If set, internal events occuring inside SDK will be printed to debugger console if their level is equal or greater than `verbosityLevel`.
    /// Default is `nil`.
    public static var verbosityLevel: LogLevel? = nil

    public static func setUserInfo(
        id: String? = nil, // swiftlint:disable:this identifier_name
        name: String? = nil,
        email: String? = nil
    ) {
        instance?.userInfoProvider.value = UserInfo(id: id, name: name, email: email)
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
