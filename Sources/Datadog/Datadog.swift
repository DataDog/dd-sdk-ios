/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// SDK version associated with logs.
/// Should be synced with SDK releases.
internal let sdkVersion = "1.1.0"

/// Datadog SDK configuration object.
public class Datadog {
    /// Provides information about the app.
    public struct AppContext {
        internal let environment: Environment
        internal let bundleIdentifier: String?
        internal let bundleVersion: String?
        internal let bundleShortVersion: String?
        internal let executableName: String?
        /// Describes current mobile device if SDK runs on a platform that supports `UIKit`.
        internal let mobileDevice: MobileDevice?

        public init(mainBundle: Bundle = Bundle.main) {
            self.init(
                environment: mainBundle.bundlePath.hasSuffix(".appex") ? .iOSAppExtension : .iOSApp,
                bundleIdentifier: mainBundle.bundleIdentifier,
                bundleVersion: mainBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                bundleShortVersion: mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                executableName: mainBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                mobileDevice: MobileDevice.current
            )
        }

        internal init(
            environment: Environment,
            bundleIdentifier: String?,
            bundleVersion: String?,
            bundleShortVersion: String?,
            executableName: String?,
            mobileDevice: MobileDevice?
        ) {
            self.environment = environment
            self.bundleIdentifier = bundleIdentifier
            self.bundleVersion = bundleVersion
            self.bundleShortVersion = bundleShortVersion
            self.executableName = executableName
            self.mobileDevice = mobileDevice
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
            consolePrint("🔥 \(error)")
        }
    }

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

    // MARK: - Internal

    internal static var instance: Datadog?

    internal let userInfoProvider: UserInfoProvider

    private static func initializeOrThrow(appContext: AppContext, configuration: Configuration) throws {
        guard Datadog.instance == nil else {
            throw ProgrammerError(description: "SDK is already initialized.")
        }
        let logsUploadURLProvider = try UploadURLProvider(
            endpointURL: configuration.logsEndpoint.url,
            clientToken: configuration.clientToken,
            dateProvider: SystemDateProvider()
        )

        let performance = PerformancePreset.best(for: appContext.environment)
        let dateProvider = SystemDateProvider()
        let userInfoProvider = UserInfoProvider()
        let networkConnectionInfoProvider = NetworkConnectionInfoProvider()
        let carrierInfoProvider = CarrierInfoProvider()

        self.instance = Datadog(
            userInfoProvider: userInfoProvider
        )

        // Initialize features:

        let httpClient = HTTPClient()

        LoggingFeature.instance = LoggingFeature(
            directory: try obtainLoggingFeatureDirectory(),
            appContext: appContext,
            performance: performance,
            httpClient: httpClient,
            logsUploadURLProvider: logsUploadURLProvider,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
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

        // Deinitialize features:

        LoggingFeature.instance = nil
        Datadog.instance = nil
    }
}

/// Convenience typealias.
internal typealias AppContext = Datadog.AppContext

/// An exception thrown due to programmer error when calling SDK public API.
/// It make the SDK non-functional and print the error to developer in debugger console..
/// When thrown, check if configuration passed to `Datadog.initialize(...)` is correct
/// and if you not call any other SDK methods before it returns.
internal struct ProgrammerError: Error, CustomStringConvertible {
    init(description: String) { self.description = "Datadog SDK usage error: \(description)" }
    let description: String
}

/// An exception thrown internally by SDK.
/// It is always handled by SDK and never passed to the user until `Datadog.verbosity` is set (then it might be printed in debugger console).
/// `InternalError` might be thrown due to SDK internal inconsistency or external issues (e.g.  I/O errors). The SDK
/// should always recover from that failures.
internal struct InternalError: Error, CustomStringConvertible {
    let description: String
}
