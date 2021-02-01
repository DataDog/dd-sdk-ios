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

        public init(mainBundle: Bundle = Bundle.main) {
            let bundleVersion = mainBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            let bundleShortVersion = mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

            self.init(
                bundleType: mainBundle.bundlePath.hasSuffix(".appex") ? .iOSAppExtension : .iOSApp,
                bundleIdentifier: mainBundle.bundleIdentifier,
                bundleVersion: bundleShortVersion ?? bundleVersion,
                bundleName: mainBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            )
        }

        internal init(
            bundleType: BundleType,
            bundleIdentifier: String?,
            bundleVersion: String?,
            bundleName: String?
        ) {
            self.bundleType = bundleType
            self.bundleIdentifier = bundleIdentifier
            self.bundleVersion = bundleVersion
            self.bundleName = bundleName
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
    public static var debugRUM: Bool = false {
        didSet {
            (Global.rum as? RUMMonitor)?.enableRUMDebugging(debugRUM)
        }
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
        instance?.userInfoProvider.value = UserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    public static func set(trackingConsent: TrackingConsent) {
        instance?.consentProvider.changeConsent(to: trackingConsent)
    }

    // MARK: - Internal

    internal static var instance: Datadog?

    internal let consentProvider: ConsentProvider
    internal let userInfoProvider: UserInfoProvider
    internal let launchTimeProvider: LaunchTimeProviderType

    private static func initializeOrThrow(
        initialTrackingConsent: TrackingConsent,
        configuration: FeaturesConfiguration
    ) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "SDK is already initialized.")
        }

        let consentProvider = ConsentProvider(initialConsent: initialTrackingConsent)
        let dateProvider = SystemDateProvider()
        let dateCorrector = DateCorrector(
            deviceDateProvider: dateProvider,
            serverDateProvider: NTPServerDateProvider()
        )
        let userInfoProvider = UserInfoProvider()
        let networkConnectionInfoProvider = NetworkConnectionInfoProvider()
        let carrierInfoProvider = CarrierInfoProvider()
        let launchTimeProvider = LaunchTimeProvider()

        // First, initialize internal loggers:

        let internalLoggerConfiguration = InternalLoggerConfiguration(
            applicationVersion: configuration.common.applicationVersion,
            environment: configuration.common.environment,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )

        userLogger = createSDKUserLogger(configuration: internalLoggerConfiguration)
        developerLogger = createSDKDeveloperLogger(configuration: internalLoggerConfiguration)

        // Then, initialize features:

        var logging: LoggingFeature?
        var tracing: TracingFeature?
        var rum: RUMFeature?
        var crashReporting: CrashReportingFeature?

        var urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?
        var rumAutoInstrumentation: RUMAutoInstrumentation?

        let commonDependencies = FeaturesCommonDependencies(
            consentProvider: consentProvider,
            performance: configuration.common.performance,
            httpClient: HTTPClient(),
            mobileDevice: MobileDevice.current,
            dateProvider: dateProvider,
            dateCorrector: dateCorrector,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            launchTimeProvider: launchTimeProvider
        )

        if let loggingConfiguration = configuration.logging {
            logging = LoggingFeature(
                directories: try obtainLoggingFeatureDirectories(),
                configuration: loggingConfiguration,
                commonDependencies: commonDependencies
            )
        }

        if let tracingConfiguration = configuration.tracing {
            tracing = TracingFeature(
                directories: try obtainTracingFeatureDirectories(),
                configuration: tracingConfiguration,
                commonDependencies: commonDependencies,
                loggingFeatureAdapter: logging.flatMap { LoggingForTracingAdapter(loggingFeature: $0) },
                tracingUUIDGenerator: DefaultTracingUUIDGenerator()
            )
        }

        if let rumConfiguration = configuration.rum {
            rum = RUMFeature(
                directories: try obtainRUMFeatureDirectories(),
                configuration: rumConfiguration,
                commonDependencies: commonDependencies
            )
            if let autoInstrumentationConfiguration = rumConfiguration.autoInstrumentation {
                rumAutoInstrumentation = RUMAutoInstrumentation(
                    configuration: autoInstrumentationConfiguration,
                    dateProvider: dateProvider
                )
            }
        }

        if let crashReportingConfiguration = configuration.crashReporting {
            crashReporting = CrashReportingFeature(
                configuration: crashReportingConfiguration,
                loggingIntegration: logging.flatMap { CrashReportingWithLoggingIntegration(loggingFeature: $0) },
                rumIntegration: rum.flatMap { CrashReportingWithRUMIntegration(rumFeature: $0) }
            )
        }

        if let urlSessionAutoInstrumentationConfiguration = configuration.urlSessionAutoInstrumentation {
            urlSessionAutoInstrumentation = URLSessionAutoInstrumentation(
                configuration: urlSessionAutoInstrumentationConfiguration,
                dateProvider: dateProvider
            )
        }

        LoggingFeature.instance = logging
        TracingFeature.instance = tracing
        RUMFeature.instance = rum
        CrashReportingFeature.instance = crashReporting

        RUMAutoInstrumentation.instance = rumAutoInstrumentation
        RUMAutoInstrumentation.instance?.enable()

        URLSessionAutoInstrumentation.instance = urlSessionAutoInstrumentation
        URLSessionAutoInstrumentation.instance?.enable()

        // Only after all features were initialized with no error thrown:
        self.instance = Datadog(
            consentProvider: consentProvider,
            userInfoProvider: userInfoProvider,
            launchTimeProvider: launchTimeProvider
        )

        // After everything is set up, send crash report if available
        CrashReportingFeature.instance?.sendCrashReportIfFound()
    }

    internal init(
        consentProvider: ConsentProvider,
        userInfoProvider: UserInfoProvider,
        launchTimeProvider: LaunchTimeProviderType
    ) {
        self.consentProvider = consentProvider
        self.userInfoProvider = userInfoProvider
        self.launchTimeProvider = launchTimeProvider
    }

    /// Internal feature made only for tests purpose.
    static func deinitializeOrThrow() throws {
        guard Datadog.instance != nil else {
            throw ProgrammerError(description: "Attempted to stop SDK before it was initialized.")
        }

        // First, reset internal loggers:
        userLogger = createNoOpSDKUserLogger()
        developerLogger = nil

        // Then, deinitialize features:
        LoggingFeature.instance = nil
        TracingFeature.instance = nil
        RUMFeature.instance = nil
        CrashReportingFeature.instance = nil

        RUMAutoInstrumentation.instance = nil
        URLSessionAutoInstrumentation.instance = nil

        // Deinitialize `Datadog`:
        Datadog.instance = nil
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
