/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

//swiftlint:disable duplicate_imports
@_exported import enum DatadogInternal.TrackingConsent
@_exported import protocol DatadogInternal.DatadogCoreProtocol
//swiftlint:enable duplicate_imports

/// An entry point to Datadog SDK.
///
/// Initialize the core instance of the Datadog SDK prior to enabling any Product.
///
/// ```swift
/// Datadog.initialize(
///     with: Datadog.Configuration(clientToken: "<client token>", env: "<environment>"),
///     trackingConsent: .pending
/// )
/// ```
///
/// Once Datadog SDK is initialized, you can enable products, such as RUM:
///
/// ```swift
/// RUM.enable(
///     with: RUM.Configuration(applicationID: "<application>")
/// )
/// ```
///     
public enum Datadog {
    /// Configuration of Datadog SDK.
    public struct Configuration {
        /// Defines the Datadog SDK policy when batching data together before uploading it to Datadog servers.
        /// Smaller batches mean smaller but more network requests, whereas larger batches mean fewer but larger network requests.
        public enum BatchSize {
            /// Prefer small sized data batches.
            case small
            /// Prefer medium sized data batches.
            case medium
            /// Prefer large sized data batches.
            case large
        }

        /// Defines the frequency at which Datadog SDK will try to upload data batches.
        public enum UploadFrequency {
            /// Try to upload batched data frequently.
            case frequent
            /// Try to upload batched data with a medium frequency.
            case average
            /// Try to upload batched data rarely.
            case rare
        }

        /// Defines the maximum amount of batches processed sequentially without a delay within one reading/uploading cycle.
        public enum BatchProcessingLevel {
            case low
            case medium
            case high

            var maxBatchesPerUpload: Int {
                switch self {
                case .low:
                    return 5
                case .medium:
                    return 20
                case .high:
                    return 100
                }
            }
        }

        /// Either the RUM client token (which supports RUM, Logging and APM) or regular client token, only for Logging and APM.
        public var clientToken: String

        /// The environment name which will be sent to Datadog. This can be used
        /// To filter events on different environments (e.g. "staging" or "production").
        public var env: String

        /// The Datadog server site where data is sent.
        ///
        /// Default value is `.us1`.
        public var site: DatadogSite

        /// The service name associated with data send to Datadog.
        ///
        /// Default value is set to application bundle identifier.
        public var service: String?

        /// The preferred size of batched data uploaded to Datadog servers.
        /// This value impacts the size and number of requests performed by the SDK.
        ///
        /// `.medium` by default.
        public var batchSize: BatchSize

        /// The preferred frequency of uploading data to Datadog servers.
        /// This value impacts the frequency of performing network requests by the SDK.
        ///
        /// `.average` by default.
        public var uploadFrequency: UploadFrequency

        /// Proxy configuration attributes.
        /// This can be used to a enable a custom proxy for uploading tracked data to Datadog's intake.
        ///
        /// Ref.: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/1411499-connectionproxydictionary
        public var proxyConfiguration: [AnyHashable: Any]?

        /// SeData encryption to use for on-disk data persistency by providing an object
        /// complying with `DataEncryption` protocol.
        public var encryption: DataEncryption?

        /// A custom NTP synchronization interface.
        ///
        /// By default, the Datadog SDK synchronizes with dedicated NTP pools provided by the
        /// https://www.ntppool.org/ . Using different pools or setting a no-op `ServerDateProvider`
        /// implementation will result in desynchronization of the SDK instance and the Datadog servers.
        /// This can lead to significant time shift in RUM sessions or distributed traces.
        public var serverDateProvider: ServerDateProvider

        /// The bundle object that contains the current executable.
        public var bundle: Bundle

        /// Batch provessing level, defining the maximum number of batches processed sequencially without a delay within one reading/uploading cycle.
        ///
        /// `.medium` by default.
        public var batchProcessingLevel: BatchProcessingLevel

        /// Flag that determines if UIApplication methods [`beginBackgroundTask(expirationHandler:)`](https://developer.apple.com/documentation/uikit/uiapplication/1623031-beginbackgroundtaskwithexpiratio) and [`endBackgroundTask:`](https://developer.apple.com/documentation/uikit/uiapplication/1622970-endbackgroundtask)
        /// are utilized to perform background uploads. It may extend the amount of time the app is operating in background by 30 seconds.
        ///
        /// Tasks are normally stopped when there's nothing to upload or when encountering any upload blocker such us no internet connection or low battery.
        ///
        /// `false` by default.
        public var backgroundTasksEnabled: Bool

        /// Creates a Datadog SDK Configuration object.
        ///
        /// - Parameters:
        ///   - clientToken:                Either the RUM client token (which supports RUM, Logging and APM) or regular client token,
        ///                                 only for Logging and APM.
        ///
        ///   - env:                        The environment name which will be sent to Datadog. This can be used
        ///                                 To filter events on different environments (e.g. "staging" or "production").
        ///
        ///   - site:                       Datadog site endpoint, default value is `.us1`.
        ///
        ///   - service:                    The service name associated with data send to Datadog.
        ///                                 Default value is set to application bundle identifier.
        ///
        ///   - bundle:                     The bundle object that contains the current executable.
        ///
        ///   - batchSize:                  The preferred size of batched data uploaded to Datadog servers.
        ///                                 This value impacts the size and number of requests performed by the SDK.
        ///                                 `.medium` by default.
        ///
        ///   - uploadFrequency:            The preferred frequency of uploading data to Datadog servers.
        ///                                 This value impacts the frequency of performing network requests by the SDK.
        ///                                 `.average` by default.
        ///
        ///   - proxyConfiguration:         A proxy configuration attributes.
        ///                                 This can be used to a enable a custom proxy for uploading tracked data to Datadog's intake.
        ///
        ///   - encryption:                 Data encryption to use for on-disk data persistency by providing an object
        ///                                 complying with `DataEncryption` protocol.
        ///
        ///   - serverDateProvider:         A custom NTP synchronization interface.
        ///                                 By default, the Datadog SDK synchronizes with dedicated NTP pools provided by the
        ///                                 https://www.ntppool.org/ . Using different pools or setting a no-op `ServerDateProvider`
        ///                                 implementation will result in desynchronization of the SDK instance and the Datadog servers.
        ///                                 This can lead to significant time shift in RUM sessions or distributed traces.
        ///   - backgroundTasksEnabled:     A flag that determines if `UIApplication` methods
        ///                                 `beginBackgroundTask(expirationHandler:)` and `endBackgroundTask:`
        ///                                 are used to perform background uploads.
        ///                                 It may extend the amount of time the app is operating in background by 30 seconds.
        ///                                 Tasks are normally stopped when there's nothing to upload or when encountering
        ///                                 any upload blocker such us no internet connection or low battery.
        ///                                 By default it's set to `false`.
        public init(
            clientToken: String,
            env: String,
            site: DatadogSite = .us1,
            service: String? = nil,
            bundle: Bundle = .main,
            batchSize: BatchSize = .medium,
            uploadFrequency: UploadFrequency = .average,
            proxyConfiguration: [AnyHashable: Any]? = nil,
            encryption: DataEncryption? = nil,
            serverDateProvider: ServerDateProvider? = nil,
            batchProcessingLevel: BatchProcessingLevel = .medium,
            backgroundTasksEnabled: Bool = false
        ) {
            self.clientToken = clientToken
            self.env = env
            self.site = site
            self.service = service
            self.bundle = bundle
            self.batchSize = batchSize
            self.uploadFrequency = uploadFrequency
            self.proxyConfiguration = proxyConfiguration
            self.encryption = encryption
            self.serverDateProvider = serverDateProvider ?? DatadogNTPDateProvider()
            self.batchProcessingLevel = batchProcessingLevel
            self.backgroundTasksEnabled = backgroundTasksEnabled
        }

        // MARK: - Internal

        /// Obtains OS directory where SDK creates its root folder.
        /// All instances of the SDK use the same root folder, but each creates its own subdirectory.
        internal var systemDirectory: () throws -> Directory = { try Directory.cache() }

        /// Default process information.
        internal var processInfo: ProcessInfo = .processInfo

        /// Sets additional configuration attributes.
        /// This can be used to tweak internal features of the SDK.
        internal var additionalConfiguration: [String: Any] = [:]

        /// Default date provider used by the SDK and all products.
        internal var dateProvider: DateProvider = SystemDateProvider()

        /// Creates `HTTPClient` with given proxy configuration attributes.
        internal var httpClientFactory: ([AnyHashable: Any]?) -> HTTPClient = { proxyConfiguration in
            URLSessionClient(proxyConfiguration: proxyConfiguration)
        }

        /// The default notification center used for subscribing to app lifecycle events and system notifications.
        internal var notificationCenter: NotificationCenter = .default

        /// The default app launch handler for tracking application startup time.
        internal var appLaunchHandler: AppLaunchHandling = AppLaunchHandler.shared

        /// The default application state provider for accessing [application state](https://developer.apple.com/documentation/uikit/uiapplication/state).
        internal var appStateProvider: AppStateProvider = DefaultAppStateProvider()
    }

    /// Verbosity level of Datadog SDK. Can be used for debugging purposes.
    /// If set, internal events occuring inside SDK will be printed to debugger console if their level is equal or greater than `verbosityLevel`.
    /// Default is `nil`.
    public static var verbosityLevel: CoreLoggerLevel? {
        get { _verbosityLevel.wrappedValue }
        set { _verbosityLevel.wrappedValue = newValue }
    }

    /// The backing storage for `verbosityLevel`, ensuring efficient synchronized
    /// read/write access to the shared value.
    private static let _verbosityLevel = ReadWriteLock<CoreLoggerLevel?>(wrappedValue: nil)

    /// Returns `true` if the Datadog SDK is already initialized, `false` otherwise.
    ///
    /// - Parameter name: The name of the SDK instance to verify.
    public static func isInitialized(instanceName name: String = CoreRegistry.defaultInstanceName) -> Bool {
        CoreRegistry.instance(named: name) is DatadogCore
    }

    /// Returns the Datadog SDK instance for the given name.
    ///
    /// - Parameter name: The name of the instance to get.
    /// - Returns: The core instance if it exists, `NOPDatadogCore` instance otherwise.
    public static func sdkInstance(named name: String) -> DatadogCoreProtocol {
        CoreRegistry.instance(named: name)
    }

    /// Sets current user information.
    ///
    /// Those will be added to logs, traces and RUM events automatically.
    ///
    /// - Parameters:
    ///   - id: Mandatory User ID
    ///   - name: Name representing the user, if any
    ///   - email: User's email, if any
    ///   - extraInfo: User's custom attributes, if any
    public static func setUserInfo(
        id: String,
        name: String? = nil,
        email: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.setUserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }
    @available(*, deprecated, message: "UserInfo id property is now mandatory.")
    public static func setUserInfo(
        id: String? = nil,
        name: String? = nil,
        email: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.setUserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    /// Add custom attributes to the current user information
    ///
    /// This extra info will be added to already existing extra info that is added
    /// to  logs traces and RUM events automatically.
    ///
    /// - Parameters:
    ///   - extraInfo: User's additional custom attributes
    public static func addUserExtraInfo(
        _ extraInfo: [AttributeKey: AttributeValue?],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.addUserExtraInfo(extraInfo)
    }

    /// Sets current account information.
    ///
    /// Those will be added to logs, traces and RUM events automatically.
    ///
    /// - Parameters:
    ///   - id: Account ID
    ///   - name: Name representing the account, if any
    ///   - extraInfo: Account's custom attributes, if any
    public static func setAccountInfo(
        id: String,
        name: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.setAccountInfo(
            id: id,
            name: name,
            extraInfo: extraInfo
        )
    }

    /// Add custom attributes to the current account information
    ///
    /// This extra info will be added to already existing extra info that is added
    /// to logs traces and RUM events automatically.
    ///
    /// - Parameters:
    ///   - extraInfo: User's additional custom attributes
    public static func addAccountExtraInfo(
        _ extraInfo: [AttributeKey: AttributeValue?],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.addAccountExtraInfo(extraInfo)
    }

    /// Clear the current account information
    ///
    /// Account information will be `nil`
    /// Following Logs, Traces, RUM Events will not include the account information anymore
    ///
    /// Any active RUM Session, active RUM View at the time of call will have their `account` attribute emptied
    ///
    /// If you want to retain the current `account` on the active RUM session,
    /// you need to stop the session first by using `RUMMonitor.stopSession()`
    ///
    /// If you want to retain the current `account` on the active RUM views,
    /// you need to stop the view first by using `RUMMonitor.stopView(viewController:attributes:)`
    ///
    public static func clearAccountInfo(
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.clearAccountInfo()
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    public static func set(trackingConsent: TrackingConsent, in core: DatadogCoreProtocol = CoreRegistry.default) {
        let core = core as? DatadogCore
        core?.set(trackingConsent: trackingConsent)
    }

    /// Clears all data that has not already been sent to Datadog servers.
    public static func clearAllData(in core: DatadogCoreProtocol = CoreRegistry.default) {
        let core = core as? DatadogCore
        core?.clearAllData()
    }

    /// Stops the initialized SDK instance attached to the given name.
    ///
    /// Stopping a core instance will stop all current processes by deallocating all Features registered
    /// in the core as well as their storage & upload units.
    /// 
    /// - Parameter instanceName: the name of the instance to stop.
    public static func stopInstance(named instanceName: String = CoreRegistry.defaultInstanceName) {
        let core = CoreRegistry.unregisterInstance(named: instanceName) as? DatadogCore
        core?.stop()
    }

    /// Initializes the Datadog SDK.
    ///
    /// You **must** initialize the core instance of the Datadog SDK prior to enabling any Product.
    ///
    ///    ```swift
    ///     Datadog.initialize(
    ///         with: Datadog.Configuration(clientToken: "<client token>", env: "<environment>"),
    ///         trackingConsent: .pending
    ///     )
    ///    ```
    ///
    /// Once Datadog SDK is initialized, you can enable products, such as RUM:
    ///
    ///    ```swift
    ///     RUM.enable(
    ///         with: RUM.Configuration(applicationID: "<application>")
    ///     )
    ///    ```
    /// It is possible to initialize multiple instances of the SDK, associating them with a name.
    /// Many methods of the SDK can optionally take a SDK instance as an argument. If not provided,
    /// the call will be associated with the default (nameless) SDK instance.
    ///
    /// To use a secondary instance of the SDK, provide a name to the ``initialize`` method
    /// and use the returned instance to enable products:
    ///
    ///    ```swift
    ///     let core = Datadog.initialize(
    ///         with: Datadog.Configuration(clientToken: "<client token>", env: "<environment>"),
    ///         trackingConsent: .pending,
    ///         instanceName: "my-instance"
    ///     )
    ///
    ///     RUM.enable(
    ///         with: RUM.Configuration(applicationID: "<application>"),
    ///         in: core
    ///     )
    ///    ```
    ///
    /// - Parameters:
    ///   - configuration: the SDK configuration.
    ///   - trackingConsent: the initial state of the Data Tracking Consent given by the user of the app.
    ///   - instanceName:   The core instance name. This value will be used for data persistency and should be
    ///                     stable between application runs.
    @discardableResult
    public static func initialize(
        with configuration: Configuration,
        trackingConsent: TrackingConsent,
        instanceName: String = CoreRegistry.defaultInstanceName
    ) -> DatadogCoreProtocol {
        #if targetEnvironment(macCatalyst)
        consolePrint("⚠️ Catalyst is not officially supported by Datadog SDK: some features may NOT be functional!", .warn)
        #endif

        #if os(macOS)
        consolePrint("⚠️ macOS is not officially supported by Datadog SDK: some features may NOT be functional!", .warn)
        #endif

        #if swift(>=5.9) && os(visionOS)
        consolePrint("⚠️ visionOS is not officially supported by Datadog SDK: some features may NOT be functional!", .warn)
        #endif

        do {
            return try initializeOrThrow(
                with: configuration,
                trackingConsent: trackingConsent,
                instanceName: instanceName
            )
        } catch {
            consolePrint("\(error)", .error)
            return NOPDatadogCore()
        }
    }

    private static func initializeOrThrow(
        with configuration: Configuration,
        trackingConsent: TrackingConsent,
        instanceName: String
    ) throws -> DatadogCoreProtocol {
        guard !CoreRegistry.isRegistered(instanceName: instanceName) else {
            throw ProgrammerError(description: "The '\(instanceName)' instance of SDK is already initialized.")
        }

        registerObjcExceptionHandlerOnce()

        try isValid(clientToken: configuration.clientToken)
        try isValid(env: configuration.env)

        let core = try DatadogCore(
            configuration: configuration,
            trackingConsent: trackingConsent,
            instanceName: instanceName
        )

        CITestIntegration.active?.startIntegration()

        CoreRegistry.register(core, named: instanceName)
        deleteV1Folders(in: core)

        DD.logger = InternalLogger(
            dateProvider: configuration.dateProvider,
            timeZone: .current,
            printFunction: consolePrint,
            verbosityLevel: { Datadog.verbosityLevel }
        )

        return core
    }

    private static func deleteV1Folders(in core: DatadogCore) {
        let deprecated = ["com.datadoghq.logs", "com.datadoghq.traces", "com.datadoghq.rum"].compactMap {
            try? Directory.cache().subdirectory(path: $0) // ignore errors - deprecated paths likely do not exist
        }

        core.readWriteQueue.async {
            // ignore errors
            deprecated.forEach { try? FileManager.default.removeItem(at: $0.url) }
        }
    }

    /// Flushes all authorised data for each feature, tears down and deinitializes the SDK.
    /// - It flushes all data authorised for each feature by performing its arbitrary upload (without retrying).
    /// - It completes all pending asynchronous work in each feature.
    ///
    /// This is highly experimental API and only supported in tests.
#if DD_SDK_COMPILED_FOR_TESTING
    public static func flushAndDeinitialize(instanceName: String = CoreRegistry.defaultInstanceName) {
        internalFlushAndDeinitialize(instanceName: instanceName)
    }
#endif

    internal static func internalFlushAndDeinitialize(instanceName: String = CoreRegistry.defaultInstanceName) {
        // Unregister core instance:
        let core = CoreRegistry.unregisterInstance(named: instanceName) as? DatadogCore
        // Flush and tear down SDK core:
        core?.flushAndTearDown()
    }
}

private func isValid(env: String) throws {
    /// 1. cannot be more than 200 chars (including `env:` prefix)
    /// 2. cannot end with `:`
    /// 3. can contain letters, numbers and _:./-_ (other chars are converted to _ at backend)
    let regex = #"^[a-zA-Z0-9_:./-]{0,195}[a-zA-Z0-9_./-]$"#
    if env.range(of: regex, options: .regularExpression, range: nil, locale: nil) == nil {
        throw ProgrammerError(description: "`env`: \(env) contains illegal characters (only alphanumerics and `_` are allowed)")
    }
}

private func isValid(clientToken: String) throws {
    if clientToken.isEmpty {
        throw ProgrammerError(description: "`clientToken` cannot be empty.")
    }
}

extension DatadogCore {
    /// The primary entry point for creating a `DatadogCore` instance.
    ///
    /// - Parameters:
    ///   - configuration: A configuration object that encapsulates both user-defined options and internal dependencies
    ///     passed to SDK's downstream components.
    ///   - trackingConsent: The user's consent regarding data tracking for the SDK.
    ///   - instanceName: A unique name for this SDK instance.
    convenience init(
        configuration: Datadog.Configuration,
        trackingConsent: TrackingConsent,
        instanceName: String
    ) throws {
        let debug = configuration.processInfo.arguments.contains(LaunchArguments.Debug)
        if debug {
            consolePrint("⚠️ Overriding verbosity, upload frequency, and sample rates due to \(LaunchArguments.Debug) launch argument", .warn)
            Datadog.verbosityLevel = .debug
        }

        let applicationVersion = configuration.additionalConfiguration[CrossPlatformAttributes.version] as? String
            ?? configuration.bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? configuration.bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0.0.0"

        let applicationBuildNumber = configuration.bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"

        let bundleName = configuration.bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        let bundleType = BundleType(bundle: configuration.bundle)
        let bundleIdentifier = configuration.bundle.bundleIdentifier ?? "unknown"
        let service = configuration.service ?? configuration.bundle.bundleIdentifier ?? "ios"
        let source = configuration.additionalConfiguration[CrossPlatformAttributes.ddsource] as? String ?? "ios"
        let variant = configuration.additionalConfiguration[CrossPlatformAttributes.variant] as? String
        let sdkVersion = configuration.additionalConfiguration[CrossPlatformAttributes.sdkVersion] as? String ?? __sdkVersion
        let buildId = configuration.additionalConfiguration[CrossPlatformAttributes.buildId] as? String
        let nativeSourceType = configuration.additionalConfiguration[CrossPlatformAttributes.nativeSourceType] as? String

        let performance = PerformancePreset(
            batchSize: debug ? .small : configuration.batchSize,
            uploadFrequency: debug ? .frequent : configuration.uploadFrequency,
            bundleType: bundleType,
            batchProcessingLevel: configuration.batchProcessingLevel
        )
        let isRunFromExtension = bundleType == .iOSAppExtension

        self.init(
            directory: try CoreDirectory(
                in: configuration.systemDirectory(),
                instanceName: instanceName,
                site: configuration.site
            ),
            dateProvider: configuration.dateProvider,
            initialConsent: trackingConsent,
            performance: performance,
            httpClient: configuration.httpClientFactory(configuration.proxyConfiguration),
            encryption: configuration.encryption,
            contextProvider: DatadogContextProvider(
                site: configuration.site,
                clientToken: configuration.clientToken,
                service: service,
                env: configuration.env,
                version: applicationVersion,
                buildNumber: applicationBuildNumber,
                buildId: buildId,
                variant: variant,
                source: source,
                nativeSourceOverride: nativeSourceType,
                sdkVersion: sdkVersion,
                ciAppOrigin: CITestIntegration.active?.origin,
                applicationName: bundleName ?? bundleType.rawValue,
                applicationBundleIdentifier: bundleIdentifier,
                applicationBundleType: bundleType,
                applicationVersion: applicationVersion,
                sdkInitDate: configuration.dateProvider.now,
                device: DeviceInfo(processInfo: configuration.processInfo),
                locale: LocaleInfo(),
                processInfo: configuration.processInfo,
                dateProvider: configuration.dateProvider,
                serverDateProvider: configuration.serverDateProvider,
                notificationCenter: configuration.notificationCenter,
                appLaunchHandler: configuration.appLaunchHandler,
                appStateProvider: configuration.appStateProvider
            ),
            applicationVersion: applicationVersion,
            maxBatchesPerUpload: configuration.batchProcessingLevel.maxBatchesPerUpload,
            backgroundTasksEnabled: configuration.backgroundTasksEnabled,
            isRunFromExtension: isRunFromExtension
        )

        telemetry.configuration(
            backgroundTasksEnabled: configuration.backgroundTasksEnabled,
            batchProcessingLevel: Int64(exactly: configuration.batchProcessingLevel.maxBatchesPerUpload),
            batchSize: performance.uploaderWindow.toInt64Milliseconds,
            batchUploadFrequency: performance.minUploadDelay.toInt64Milliseconds,
            useLocalEncryption: configuration.encryption != nil,
            useProxy: configuration.proxyConfiguration != nil
        )
    }
}
