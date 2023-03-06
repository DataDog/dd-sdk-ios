/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogLogs

/// Datadog SDK configuration object.
public class Datadog {
    /// Provides information about the app.
    public struct AppContext {
        internal let bundleType: BundleType
        internal let bundleIdentifier: String?
        /// Executable version (i.e. application version or app extension version)
        internal let bundleVersion: String?
        /// Executable name (i.e. application name or app extension name)
        internal let bundleName: String?
        /// Process info
        internal let processInfo: ProcessInfo

        public init(mainBundle: Bundle = Bundle.main, processInfo: ProcessInfo = ProcessInfo.processInfo) {
            let bundleVersion = mainBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            let bundleShortVersion = mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

            self.init(
                bundleType: mainBundle.bundlePath.hasSuffix(".appex") ? .iOSAppExtension : .iOSApp,
                bundleIdentifier: mainBundle.bundleIdentifier,
                bundleVersion: bundleShortVersion ?? bundleVersion,
                bundleName: mainBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                processInfo: processInfo
            )
        }

        internal init(
            bundleType: BundleType,
            bundleIdentifier: String?,
            bundleVersion: String?,
            bundleName: String?,
            processInfo: ProcessInfo
        ) {
            self.bundleType = bundleType
            self.bundleIdentifier = bundleIdentifier
            self.bundleVersion = bundleVersion
            self.bundleName = bundleName
            self.processInfo = processInfo
        }
    }

    /// Initializes the Datadog SDK.
    /// - Parameters:
    ///   - appContext: context passing information about the app.
    ///   - configuration: the SDK configuration obtained using `Datadog.Configuration.builderUsing(...)`.
    @available(*, deprecated, message: """
    This method is deprecated and uses the `TrackingConsent.granted` value as a default privacy consent.
    This means that the SDK will start recording and sending data immediately after initialisation without waiting for the user's consent to be given.

    Use `Datadog.initialize(appContext:trackingConsent:configuration:)` and set consent to `.granted` to preserve previous behaviour.
    """)
    public static func initialize(appContext: AppContext, configuration: Configuration) {
        initialize(
            appContext: appContext,
            trackingConsent: .granted,
            configuration: configuration
        )
    }

    /// Initializes the Datadog SDK.
    /// - Parameters:
    ///   - appContext: context passing information about the app.
    ///   - trackingConsent: the initial state of the Data Tracking Consent given by the user of the app.
    ///   - configuration: the SDK configuration obtained using `Datadog.Configuration.builderUsing(...)`.
    public static func initialize(
        appContext: AppContext,
        trackingConsent: TrackingConsent,
        configuration: Configuration
    ) {
        // TODO: RUMM-511 remove this warning
        #if targetEnvironment(macCatalyst)
        consolePrint("⚠️ Catalyst is not officially supported by Datadog SDK: some features may NOT be functional!")
        #endif

        do {
            try initializeOrThrow(
                initialTrackingConsent: trackingConsent,
                configuration: try FeaturesConfiguration(
                    configuration: configuration,
                    appContext: appContext
                )
            )

            // Now that RUM is potentially initialized, override the debugRUM value
            let debugRumOverride = appContext.processInfo.arguments.contains(LaunchArguments.DebugRUM)
            if debugRumOverride {
                consolePrint("⚠️ Overriding RUM debugging due to \(LaunchArguments.DebugRUM) launch argument")
                Datadog.debugRUM = true
            }
        } catch {
            consolePrint("\(error)")
        }
    }

    /// Verbosity level of Datadog SDK. Can be used for debugging purposes.
    /// If set, internal events occuring inside SDK will be printed to debugger console if their level is equal or greater than `verbosityLevel`.
    /// Default is `nil`.
    public static var verbosityLevel: CoreLoggerLevel? = nil

    /// Utility setting to inspect the active RUM View.
    /// If set, a debugging outline will be displayed on top of the application, describing the name of the active RUM View.
    /// May be used to debug issues with RUM instrumentation in your app.
    /// Default is `false`.
    public static var debugRUM = false {
        didSet {
            (Global.rum as? RUMMonitor)?.enableRUMDebugging(debugRUM)
        }
    }

    /// Returns `true` if the Datadog SDK is already initialized, `false` otherwise.
    public static var isInitialized: Bool {
        return defaultDatadogCore is DatadogCore
    }

    /// Sets current user information.
    /// Those will be added to logs, traces and RUM events automatically.
    /// - Parameters:
    ///   - id: User ID, if any
    ///   - name: Name representing the user, if any
    ///   - email: User's email, if any
    ///   - extraInfo: User's custom attributes, if any
    public static func setUserInfo(
        id: String? = nil,
        name: String? = nil,
        email: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:]
    ) {
        let core = defaultDatadogCore as? DatadogCore
        core?.setUserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    /// Add custom attributes  to the current user information
    ///
    /// This extra info will be added to already existing extra info that is added
    /// to  logs traces and RUM events automatically.
    /// - Parameters:
    ///   - extraInfo: User's additionall custom attributes
    public static func addUserExtraInfo(
        _ extraInfo: [AttributeKey: AttributeValue?]
    ) {
        let core = defaultDatadogCore as? DatadogCore
        core?.addUserExtraInfo(extraInfo)
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    public static func set(trackingConsent: TrackingConsent) {
        let core = defaultDatadogCore as? DatadogCore
        core?.set(trackingConsent: trackingConsent)
    }

    /// Clears all data that has not already been sent to Datadog servers.
    public static func clearAllData() {
        let core = defaultDatadogCore as? DatadogCore
        core?.clearAllData()
    }

    // MARK: - Internal
    internal struct LaunchArguments {
        static let Debug = "DD_DEBUG"
        static let DebugRUM = "DD_DEBUG_RUM"
    }

    private static func initializeOrThrow(
        initialTrackingConsent: TrackingConsent,
        configuration: FeaturesConfiguration
    ) throws {
        if Datadog.isInitialized {
            throw ProgrammerError(description: "SDK is already initialized.")
        }

        let userInfoProvider = UserInfoProvider()
        let serverDateProvider = configuration.common.serverDateProvider ?? DatadogNTPDateProvider()
        let appStateListener = AppStateListener(dateProvider: configuration.common.dateProvider)

        // Set default `DatadogCore`:
        let core = DatadogCore(
            directory: try CoreDirectory(in: Directory.cache(), from: configuration.common),
            dateProvider: configuration.common.dateProvider,
            initialConsent: initialTrackingConsent,
            userInfoProvider: userInfoProvider,
            performance: configuration.common.performance,
            httpClient: HTTPClient(proxyConfiguration: configuration.common.proxyConfiguration),
            encryption: configuration.common.encryption,
            contextProvider: DatadogContextProvider(
                configuration: configuration.common,
                device: .init(),
                serverDateProvider: serverDateProvider
            ),
            applicationVersion: configuration.common.applicationVersion
        )

        // First, initialize features:
        var rum: RUMFeature?

        var urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?
        var rumInstrumentation: RUMInstrumentation?

        var telemetry: RUMTelemetry?

        if let rumConfiguration = configuration.rum {
            telemetry = RUMTelemetry(
                in: core,
                dateProvider: rumConfiguration.dateProvider,
                configurationEventMapper: nil,
                delayedDispatcher: nil,
                sampler: rumConfiguration.telemetrySampler
            )

            rum = try core.create(
                configuration: createRUMConfiguration(configuration: rumConfiguration),
                featureSpecificConfiguration: rumConfiguration
            )

            core.register(feature: rum)

            if let instrumentationConfiguration = rumConfiguration.instrumentation {
                rumInstrumentation = RUMInstrumentation(
                    configuration: instrumentationConfiguration,
                    dateProvider: rumConfiguration.dateProvider
                )

                core.register(feature: rumInstrumentation)
            }
        }

        if let loggingConfiguration = configuration.logging {
            try DatadogLogger.initialise(
                in: core,
                intake: loggingConfiguration.customURL.map { .custom($0) } ?? .datadog,
                applicationBundleIdentifier: loggingConfiguration.applicationBundleIdentifier,
                eventMapper: loggingConfiguration.logEventMapper,
                dateProvider: loggingConfiguration.dateProvider,
                sampler: loggingConfiguration.remoteLoggingSampler
            )
        }

        if let urlSessionAutoInstrumentationConfiguration = configuration.urlSessionAutoInstrumentation {
            urlSessionAutoInstrumentation = URLSessionAutoInstrumentation(
                configuration: urlSessionAutoInstrumentationConfiguration,
                dateProvider: configuration.common.dateProvider,
                appStateListener: appStateListener
            )

            core.register(feature: urlSessionAutoInstrumentation)
        }

        core.v1.feature(RUMInstrumentation.self)?.enable()
        core.v1.feature(URLSessionAutoInstrumentation.self)?.enable()

        defaultDatadogCore = core

        // After everything is set up, if the Crash Reporting feature was enabled,
        // register crash reporter and send crash report if available:
        if
            let configuration = configuration.crashReporting,
            let reporter = CrashReporter(core: core, configuration: configuration)
        {
            try core.register(feature: reporter)
            reporter.sendCrashReportIfFound()
        }

        deleteV1Folders(in: core)

        DD.logger = InternalLogger(
            dateProvider: SystemDateProvider(),
            timeZone: .current,
            printFunction: consolePrint,
            verbosityLevel: { Datadog.verbosityLevel }
        )

        telemetry?.configuration(configuration: configuration)
        DD.telemetry = telemetry ?? NOPTelemetry()
    }

    public init() {
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
    public static func flushAndDeinitialize() {
        internalFlushAndDeinitialize()
    }
#endif

    internal static func internalFlushAndDeinitialize() {
        assert(Datadog.isInitialized, "SDK must be first initialized.")

        // Flush and tear down SDK core:
        (defaultDatadogCore as? DatadogCore)?.flushAndTearDown()

        // Reset Globals:
        Global.sharedTracer = DDNoopGlobals.tracer
        Global.rum = DDNoopRUMMonitor()
        DD.telemetry = NOPTelemetry()

        // Deinitialize `Datadog`:
        defaultDatadogCore = NOPDatadogCore()
    }
}

/// Convenience typealias.
internal typealias AppContext = Datadog.AppContext
