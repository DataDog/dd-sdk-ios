/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogRUM

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
    ///
    /// - Parameters:
    ///   - appContext: context passing information about the app.
    ///   - trackingConsent: the initial state of the Data Tracking Consent given by the user of the app.
    ///   - configuration: the SDK configuration obtained using `Datadog.Configuration.builderUsing(...)`.
    ///   - instanceName: The core instance name.
    public static func initialize(
        appContext: AppContext,
        trackingConsent: TrackingConsent,
        configuration: Configuration,
        instanceName: String = CoreRegistry.defaultInstanceName
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
                ),
                instanceName: instanceName
            )
        } catch {
            consolePrint("\(error)")
        }
    }

    /// Verbosity level of Datadog SDK. Can be used for debugging purposes.
    /// If set, internal events occuring inside SDK will be printed to debugger console if their level is equal or greater than `verbosityLevel`.
    /// Default is `nil`.
    public static var verbosityLevel: CoreLoggerLevel? = nil

    /// Returns `true` if the Datadog SDK is already initialized, `false` otherwise.
    public static var isInitialized: Bool {
        return CoreRegistry.default is DatadogCore
    }

    /// Returns the Datadog SDK instance for the given name.
    ///
    /// - Parameter name: The name of the instance to get.
    /// - Returns: The core instance if it exists, `NOPDatadogCore` instance otherwise.
    public static func sdkInstance(named name: String) -> DatadogCoreProtocol {
        CoreRegistry.instance(named: name)
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

    /// Add custom attributes  to the current user information
    ///
    /// This extra info will be added to already existing extra info that is added
    /// to  logs traces and RUM events automatically.
    /// - Parameters:
    ///   - extraInfo: User's additionall custom attributes
    public static func addUserExtraInfo(
        _ extraInfo: [AttributeKey: AttributeValue?],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let core = core as? DatadogCore
        core?.addUserExtraInfo(extraInfo)
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

    private static func initializeOrThrow(
        initialTrackingConsent: TrackingConsent,
        configuration: FeaturesConfiguration,
        instanceName: String
    ) throws {
        if Datadog.isInitialized {
            throw ProgrammerError(description: "SDK is already initialized.")
        }

        let serverDateProvider = configuration.common.serverDateProvider ?? DatadogNTPDateProvider()

        // Set default `DatadogCore`:
        let core = DatadogCore(
            directory: try CoreDirectory(in: Directory.cache(), from: configuration.common),
            dateProvider: configuration.common.dateProvider,
            initialConsent: initialTrackingConsent,
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

        let telemetry = TelemetryCore(core: core)

        telemetry.configuration(
            batchSize: Int64(exactly: configuration.common.performance.maxFileSize),
            batchUploadFrequency: configuration.common.performance.minUploadDelay.toInt64Milliseconds,
            useLocalEncryption: configuration.common.encryption != nil,
            useProxy: configuration.common.proxyConfiguration != nil
        )

        // First, initialize features:
        if let rumConfiguration = configuration.rum {
            RUM.enable(with: rumConfiguration, in: core)

            CITestIntegration.active?.startIntegration()
        }

        CoreRegistry.register(core, named: instanceName)
        deleteV1Folders(in: core)

        DD.logger = InternalLogger(
            dateProvider: SystemDateProvider(),
            timeZone: .current,
            printFunction: consolePrint,
            verbosityLevel: { Datadog.verbosityLevel }
        )

        DD.telemetry = telemetry
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
        (CoreRegistry.default as? DatadogCore)?.flushAndTearDown()

        // Reset Globals:
        DD.telemetry = NOPTelemetry()

        // Deinitialize `Datadog`:
        CoreRegistry.unregisterDefault()
    }
}

/// Convenience typealias.
internal typealias AppContext = Datadog.AppContext
