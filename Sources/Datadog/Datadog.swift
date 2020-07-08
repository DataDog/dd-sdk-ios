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
    ///   - configuration: the SDK configuration obtained using `Datadog.Configuration.builderUsing(clientToken:)`.
    public static func initialize(appContext: AppContext, configuration: Configuration) {
        do {
            try initializeOrThrow(appContext: appContext, configuration: configuration)
        } catch {
            consolePrint("\(error)")
        }
    }

    /// Verbosity level of Datadog SDK. Can be used for debugging purposes.
    /// If set, internal events occuring inside SDK will be printed to debugger console if their level is equal or greater than `verbosityLevel`.
    /// Default is `nil`.
    public static var verbosityLevel: LogLevel? = nil

    public static func setUserInfo(
        id: String? = nil,
        name: String? = nil,
        email: String? = nil
    ) {
        instance?.userInfoProvider.value = UserInfo(id: id, name: name, email: email)
    }

    // MARK: - Internal

    internal static var instance: Datadog?

    internal let userInfoProvider: UserInfoProvider

    private static func initializeOrThrow(appContext: AppContext, configuration: Configuration) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "SDK is already initialized.")
        }
        let validConfiguration = try ValidConfiguration(
            configuration: configuration,
            appContext: appContext
        )

        let performance = PerformancePreset.best(for: appContext.bundleType)
        let dateProvider = SystemDateProvider()
        let userInfoProvider = UserInfoProvider()
        let networkConnectionInfoProvider = NetworkConnectionInfoProvider()
        let carrierInfoProvider = CarrierInfoProvider()

        // First, initialize internal loggers:

        let internalLoggerConfiguration = InternalLoggerConfiguration(
            applicationVersion: validConfiguration.applicationVersion,
            environment: validConfiguration.environment,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )

        userLogger = createSDKUserLogger(configuration: internalLoggerConfiguration)
        developerLogger = createSDKDeveloperLogger(configuration: internalLoggerConfiguration)

        // Then, initialize features:

        let httpClient = HTTPClient()
        let mobileDevice = MobileDevice.current

        var logging: LoggingFeature?
        var tracing: TracingFeature?

        if configuration.loggingEnabled {
            logging = LoggingFeature(
                directory: try obtainLoggingFeatureDirectory(),
                configuration: validConfiguration,
                performance: performance,
                mobileDevice: mobileDevice,
                httpClient: httpClient,
                logsUploadURLProvider: UploadURLProvider(
                    urlWithClientToken: validConfiguration.logsUploadURLWithClientToken,
                    queryItemProviders: [
                        .ddsource(),
                        .batchTime(using: dateProvider)
                    ]
                ),
                dateProvider: dateProvider,
                userInfoProvider: userInfoProvider,
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        }

        if configuration.tracingEnabled {
            tracing = TracingFeature(
                directory: try obtainTracingFeatureDirectory(),
                configuration: validConfiguration,
                performance: performance,
                loggingFeatureAdapter: logging.flatMap { LoggingForTracingAdapter(loggingFeature: $0) },
                mobileDevice: mobileDevice,
                httpClient: httpClient,
                tracesUploadURLProvider: UploadURLProvider(
                    urlWithClientToken: validConfiguration.tracesUploadURLWithClientToken,
                    queryItemProviders: [
                        .batchTime(using: dateProvider)
                    ]
                ),
                dateProvider: dateProvider,
                tracingUUIDGenerator: DefaultTracingUUIDGenerator(),
                userInfoProvider: userInfoProvider,
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        }

        LoggingFeature.instance = logging
        TracingFeature.instance = tracing
        TracingAutoInstrumentation.instance = TracingAutoInstrumentation(with: configuration)
        TracingAutoInstrumentation.instance?.apply()

        // Only after all features were initialized with no error thrown:
        self.instance = Datadog(
            userInfoProvider: userInfoProvider
        )
    }

    internal init(userInfoProvider: UserInfoProvider) {
        self.userInfoProvider = userInfoProvider
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
        TracingAutoInstrumentation.instance = nil

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
