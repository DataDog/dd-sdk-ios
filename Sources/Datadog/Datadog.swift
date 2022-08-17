/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

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
    public static var verbosityLevel: LogLevel? = nil

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

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    public static func set(trackingConsent: TrackingConsent) {
        let core = defaultDatadogCore as? DatadogCore
        core?.set(trackingConsent: trackingConsent)
    }

    /// Clears all data that has not already been sent to Datadog servers.
    public static func clearAllData() {
        let logging = defaultDatadogCore.v1.feature(LoggingFeature.self)
        let tracing = defaultDatadogCore.v1.feature(TracingFeature.self)
        let rum = defaultDatadogCore.v1.feature(RUMFeature.self)
        logging?.storage.clearAllData()
        tracing?.storage.clearAllData()
        rum?.storage.clearAllData()
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

        let consentProvider = ConsentProvider(initialConsent: initialTrackingConsent)
        let userInfoProvider = UserInfoProvider()
        let dateProvider = SystemDateProvider()
        let dateCorrector = ServerDateCorrector(
            serverDateProvider: configuration.common.serverDateProvider ?? DatadogNTPDateProvider()
        )
        let networkConnectionInfoProvider = NetworkConnectionInfoProvider()
        let carrierInfoProvider = CarrierInfoProvider()
        let launchTimeProvider = LaunchTimeProvider()
        let appVersionProvider = AppVersionProvider(configuration: configuration.common)

        // Bundle all core dependencies provided by `DatadogCore` to features:
        let commonDependencies = CoreDependencies(
            consentProvider: consentProvider,
            performance: configuration.common.performance,
            httpClient: HTTPClient(proxyConfiguration: configuration.common.proxyConfiguration),
            deviceInfo: .init(),
            batteryStatusProvider: BatteryStatusProvider(),
            sdkInitDate: dateProvider.now,
            dateProvider: dateProvider,
            dateCorrector: dateCorrector,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            launchTimeProvider: launchTimeProvider,
            appStateListener: AppStateListener(dateProvider: dateProvider),
            encryption: configuration.common.encryption
        )

        // Set default `DatadogCore`:
        let core = DatadogCore(
            directory: try CoreDirectory(in: Directory.cache(), from: configuration.common),
            configuration: configuration.common,
            dependencies: commonDependencies,
            appVersionProvider: appVersionProvider
        )

        // First, initialize features:
        var logging: LoggingFeature?
        var tracing: TracingFeature?
        var rum: RUMFeature?
        var crashReporting: CrashReportingFeature?

        var urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?
        var rumInstrumentation: RUMInstrumentation?

        if let rumConfiguration = configuration.rum {
            DD.telemetry = RUMTelemetry(
                in: core,
                sdkVersion: configuration.common.sdkVersion,
                applicationID: rumConfiguration.applicationID,
                source: configuration.common.source,
                dateProvider: dateProvider,
                dateCorrector: dateCorrector,
                sampler: rumConfiguration.telemetrySampler
            )

            rum = try core.create(
                storageConfiguration: createV2RUMStorageConfiguration(),
                uploadConfiguration: createV2RUMUploadConfiguration(v1Configuration: rumConfiguration),
                featureSpecificConfiguration: rumConfiguration
            )

            core.register(feature: rum)

            if let instrumentationConfiguration = rumConfiguration.instrumentation {
                rumInstrumentation = RUMInstrumentation(
                    configuration: instrumentationConfiguration,
                    dateProvider: dateProvider
                )

                core.register(feature: rumInstrumentation)
            }
        }

        if let loggingConfiguration = configuration.logging {
            logging = try core.create(
                storageConfiguration: createV2LoggingStorageConfiguration(),
                uploadConfiguration: createV2LoggingUploadConfiguration(v1Configuration: loggingConfiguration),
                featureSpecificConfiguration: loggingConfiguration
            )
            core.register(feature: logging)
        }

        if let tracingConfiguration = configuration.tracing {
            tracing = try core.create(
                storageConfiguration: createV2TracingStorageConfiguration(),
                uploadConfiguration: createV2TracingUploadConfiguration(v1Configuration: tracingConfiguration),
                featureSpecificConfiguration: tracingConfiguration
            )
            core.register(feature: tracing)
        }

        if let crashReportingConfiguration = configuration.crashReporting {
            crashReporting = CrashReportingFeature(
                configuration: crashReportingConfiguration,
                commonDependencies: commonDependencies
            )

            core.register(feature: crashReporting)
        }

        if let urlSessionAutoInstrumentationConfiguration = configuration.urlSessionAutoInstrumentation {
            urlSessionAutoInstrumentation = URLSessionAutoInstrumentation(
                configuration: urlSessionAutoInstrumentationConfiguration,
                commonDependencies: commonDependencies
            )

            core.register(feature: urlSessionAutoInstrumentation)
        }

        core.v1.feature(RUMInstrumentation.self)?.enable()
        core.v1.feature(URLSessionAutoInstrumentation.self)?.enable()

        defaultDatadogCore = core

        // After everything is set up, if the Crash Reporting feature was enabled,
        // register crash reporter and send crash report if available:
        if let crashReportingFeature = core.v1.feature(CrashReportingFeature.self) {
            Global.crashReporter = CrashReporter(
                crashReportingFeature: crashReportingFeature,
                loggingFeature: logging,
                rumFeature: rum,
                context: core.v1Context
            )

            Global.crashReporter?.sendCrashReportIfFound()
        }
    }

    internal init() {
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

        // Tear down and deinitialize all features:
        let logging = defaultDatadogCore.v1.feature(LoggingFeature.self)
        let tracing = defaultDatadogCore.v1.feature(TracingFeature.self)
        let rum = defaultDatadogCore.v1.feature(RUMFeature.self)
        let rumInstrumentation = defaultDatadogCore.v1.feature(RUMInstrumentation.self)
        let urlSessionInstrumentation = defaultDatadogCore.v1.feature(URLSessionAutoInstrumentation.self)
        logging?.deinitialize()
        tracing?.deinitialize()
        rum?.deinitialize()
        rumInstrumentation?.deinitialize()
        urlSessionInstrumentation?.deinitialize()

        // Reset Globals:
        Global.sharedTracer = DDNoopGlobals.tracer
        Global.rum = DDNoopRUMMonitor()
        Global.crashReporter?.deinitialize()
        Global.crashReporter = nil
        DD.telemetry = NOPTelemetry()

        // Deinitialize `Datadog`:
        defaultDatadogCore = NOOPDatadogCore()
    }

    // MARK: - Internal Proxy - exposure of internal classes (Mostly used for cross platform libraries)

    public private(set) static var _internal = _InternalProxy()
}

/// Convenience typealias.
internal typealias AppContext = Datadog.AppContext

/// An exception thrown due to programmer error when calling SDK public API.
/// It makes the SDK non-functional and print the error to developer in debugger console..
/// When thrown, check if configuration passed to `Datadog.initialize(...)` is correct
/// and if you do not call any other SDK methods before it returns.
internal struct ProgrammerError: Error, CustomStringConvertible {
    init(description: String) { self.description = "🔥 Datadog SDK usage error: \(description)" }
    let description: String
}

/// An exception thrown internally by SDK.
/// It is always handled by SDK (keeps it functional) and never passed to the user until `Datadog.verbosity` is set (then it might be printed in debugger console).
/// `InternalError` might be thrown due to programmer error (API misuse) or SDK internal inconsistency or external issues (e.g.  I/O errors). The SDK
/// should always recover from that failures.
internal struct InternalError: Error, CustomStringConvertible {
    let description: String
}
