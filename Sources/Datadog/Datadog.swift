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
        let logging = defaultDatadogCore.feature(LoggingFeature.self)
        let tracing = defaultDatadogCore.feature(TracingFeature.self)
        let rum = defaultDatadogCore.feature(RUMFeature.self)
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
        let dateCorrector = DateCorrector(
            deviceDateProvider: dateProvider,
            serverDateProvider: NTPServerDateProvider()
        )

        let networkConnectionInfoProvider = NetworkConnectionInfoProvider()
        let carrierInfoProvider = CarrierInfoProvider()
        let launchTimeProvider = LaunchTimeProvider()

        // Bundle all core dependencies provided by `DatadogCore` to features:
        let commonDependencies = CoreDependencies(
            consentProvider: consentProvider,
            performance: configuration.common.performance,
            httpClient: HTTPClient(proxyConfiguration: configuration.common.proxyConfiguration),
            mobileDevice: MobileDevice(),
            sdkInitDate: dateProvider.currentDate(),
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
            rootDirectory: try Directory.cache(),
            configuration: configuration.common,
            dependencies: commonDependencies
        )

        // First, initialize internal loggers:
        let internalLoggerConfiguration = InternalLoggerConfiguration(
            sdkVersion: configuration.common.sdkVersion,
            applicationVersion: configuration.common.applicationVersion,
            environment: configuration.common.environment,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )

        userLogger = createSDKUserLogger(configuration: internalLoggerConfiguration)

        // Then, initialize features:
        var telemetry: Telemetry?
        var logging: LoggingFeature?
        var tracing: TracingFeature?
        var rum: RUMFeature?
        var crashReporting: CrashReportingFeature?

        var urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?
        var rumInstrumentation: RUMInstrumentation?

        if let rumConfiguration = configuration.rum {
            telemetry = RUMTelemetry(
                in: core,
                sdkVersion: configuration.common.sdkVersion,
                applicationID: rumConfiguration.applicationID,
                source: rumConfiguration.common.source,
                dateProvider: dateProvider,
                dateCorrector: dateCorrector,
                sampler: rumConfiguration.telemetrySampler
            )
            core.telemetry = telemetry

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
            tracing = TracingFeature(
                directories: try obtainTracingFeatureDirectories(),
                configuration: tracingConfiguration,
                commonDependencies: commonDependencies,
                loggingFeatureAdapter: logging.map { LoggingForTracingAdapter(loggingFeature: $0) },
                telemetry: telemetry
            )

            core.register(feature: tracing)
        }

        if let crashReportingConfiguration = configuration.crashReporting {
            crashReporting = CrashReportingFeature(
                configuration: crashReportingConfiguration,
                commonDependencies: commonDependencies,
                telemetry: telemetry
            )

            core.register(feature: crashReporting)
        }

        if let urlSessionAutoInstrumentationConfiguration = configuration.urlSessionAutoInstrumentation {
            urlSessionAutoInstrumentation = URLSessionAutoInstrumentation(
                configuration: urlSessionAutoInstrumentationConfiguration,
                commonDependencies: commonDependencies
            )
        }

        core.feature(RUMInstrumentation.self)?.enable()

        URLSessionAutoInstrumentation.instance = urlSessionAutoInstrumentation
        URLSessionAutoInstrumentation.instance?.enable()

        defaultDatadogCore = core

        // After everything is set up, if the Crash Reporting feature was enabled,
        // register crash reporter and send crash report if available:
        if let crashReportingFeature = core.feature(CrashReportingFeature.self) {
            Global.crashReporter = CrashReporter(
                crashReportingFeature: crashReportingFeature,
                loggingFeature: logging,
                rumFeature: rum
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
        let logging = defaultDatadogCore.feature(LoggingFeature.self)
        let tracing = defaultDatadogCore.feature(TracingFeature.self)
        let rum = defaultDatadogCore.feature(RUMFeature.self)
        let rumInstrumentation = defaultDatadogCore.feature(RUMInstrumentation.self)
        logging?.deinitialize()
        tracing?.deinitialize()
        rum?.deinitialize()
        rumInstrumentation?.deinitialize()

        URLSessionAutoInstrumentation.instance?.deinitialize()

        // Reset Globals:
        Global.sharedTracer = DDNoopGlobals.tracer
        Global.rum = DDNoopRUMMonitor()
        Global.crashReporter?.deinitialize()
        Global.crashReporter = nil

        // Deinitialize `Datadog`:
        defaultDatadogCore = NOOPDatadogCore()

        // Reset internal loggers:
        userLogger = createNoOpSDKUserLogger()
    }
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
