/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@_exported import class DatadogInternal.CoreRegistry

@_exported import class DatadogInternal.HTTPHeadersWriter
@_exported import class DatadogInternal.B3HTTPHeadersWriter
@_exported import class DatadogInternal.W3CHTTPHeadersWriter

extension Datadog {
    /// Configuration of Datadog SDK.
    public struct Configuration {
        /// Defines the Datadog SDK policy when batching data together before uploading it to Datadog servers.
        /// Smaller batches mean smaller but more network requests, whereas larger batches mean fewer but larger network requests.
        public enum BatchSize: CaseIterable {
            /// Prefer small sized data batches.
            case small
            /// Prefer medium sized data batches.
            case medium
            /// Prefer large sized data batches.
            case large
        }

        /// Defines the frequency at which Datadog SDK will try to upload data batches.
        public enum UploadFrequency: CaseIterable {
            /// Try to upload batched data frequently.
            case frequent
            /// Try to upload batched data with a medium frequency.
            case average
            /// Try to upload batched data rarely.
            case rare
        }

        /// Defines the maximum amount of batches processed sequentially without a delay within one reading/uploading cycle.
        public enum BatchProcessingLevel: CaseIterable {
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

        /// The application version used for Unified Service Tagging.
        ///
        /// If not provided, the SDK will use the version from the application's Info.plist
        /// (`CFBundleShortVersionString` or `CFBundleVersion`).
        public var version: String?

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
        ///   - version:                    The application version used for Unified Service Tagging.
        ///                                 If not provided, the SDK will use the version from the application's Info.plist
        ///                                 (`CFBundleShortVersionString` or `CFBundleVersion`).
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
            version: String? = nil,
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
            self.version = version
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
}
