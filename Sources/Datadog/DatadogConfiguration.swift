/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Datadog {
    internal struct Constants {
        /// Value for `ddsource` send by different features.
        static let ddsource = "ios"
    }

    /// Datadog SDK configuration.
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

        /// Either the RUM client token (which supports RUM, Logging and APM) or regular client token, only for Logging and APM.
        private(set) var clientToken: String
        private(set) var environment: String
        private(set) var serverDateProvider: ServerDateProvider?

        /// If `DatadogSite` is set, it will override `logsEndpoint` and `tracesEndpoint`.
        private(set) var datadogEndpoint: DatadogSite

        private(set) var serviceName: String?
        private(set) var batchSize: BatchSize
        private(set) var uploadFrequency: UploadFrequency
        private(set) var additionalConfiguration: [String: Any]
        private(set) var proxyConfiguration: [AnyHashable: Any]?
        private(set) var encryption: DataEncryption?

        /// Creates the builder for configuring the SDK to work with Logging and Tracing features.
        /// - Parameter clientToken: client token obtained on Datadog website.
        /// - Parameter environment: the environment name which will be sent to Datadog. This can be used
        ///  to filter events on different environments (e.g. "staging" or "production").
        public static func builderUsing(clientToken: String, environment: String) -> Builder {
            return Builder(clientToken: clientToken, environment: environment)
        }

        /// `Datadog.Configuration` builder.
        ///
        /// Usage:
        ///
        ///     Datadog.Configuration.builderUsing(clientToken:environment:)
        ///                           ... // customize using builder methods
        ///                          .build()
        ///
        public class Builder {
            internal var configuration: Configuration

            /// Private initializer providing default configuration values.
            init(clientToken: String, environment: String) {
                self.configuration = Configuration(
                    clientToken: clientToken,
                    environment: environment,
                    // While `.set(<feature>Endpoint:)` APIs are deprecated, the `datadogEndpoint` default must be `nil`,
                    // so we know the clear user's intent to override deprecated values.
                    datadogEndpoint: .us1,
                    serviceName: nil,
                    batchSize: .medium,
                    uploadFrequency: .average,
                    additionalConfiguration: [:],
                    proxyConfiguration: nil
                )
            }

            /// Sets the Datadog server endpoint where data is sent.
            ///
            /// If set, it will override values set by any of these deprecated APIs:
            /// * `set(logsEndpoint:)`
            /// * `set(tracesEndpoint:)`
            ///
            /// - Parameter endpoint: server endpoint (default value is `.us`)
            public func set(endpoint: DatadogSite) -> Builder {
                configuration.datadogEndpoint = endpoint
                return self
            }

            /// Sets a custom NTP synchronization interface.
            ///
            /// By default, the Datadog SDK synchronizes with dedicated NTP pools provided by the
            /// https://www.ntppool.org/ . Using different pools or setting a no-op `ServerDateProvider`
            /// implementation will result in desynchronization of the SDK instance and the Datadog servers.
            /// This can lead to significant time shift in RUM sessions or distributed traces.
            ///
            /// - Parameter serverDateProvider: An object that complies with `ServerDateProvider`
            ///                                 for provider clock synchronisation.
            public func set(serverDateProvider: ServerDateProvider) -> Builder {
                configuration.serverDateProvider = serverDateProvider
                return self
            }

            // MARK: - Features Common Configuration

            /// Sets the default service name associated with data send to Datadog.
            /// NOTE: The `serviceName` can be also overwritten by each `Logger` instance.
            /// - Parameter serviceName: the service name (default value is set to application bundle identifier)
            public func set(serviceName: String) -> Builder {
                configuration.serviceName = serviceName
                return self
            }

            /// Sets the preferred size of batched data uploaded to Datadog servers.
            /// This value impacts the size and number of requests performed by the SDK.
            /// - Parameter batchSize: `.medium` by default.
            public func set(batchSize: BatchSize) -> Builder {
                configuration.batchSize = batchSize
                return self
            }

            /// Sets the preferred frequency of uploading data to Datadog servers.
            /// This value impacts the frequency of performing network requests by the SDK.
            /// - Parameter uploadFrequency: `.average` by default.
            public func set(uploadFrequency: UploadFrequency) -> Builder {
                configuration.uploadFrequency = uploadFrequency
                return self
            }

            /// Sets proxy configuration attributes.
            /// This can be used to a enable a custom proxy for uploading tracked data to Datadog's intake.
            /// - Parameter proxyConfiguration: `nil` by default.
            public func set(proxyConfiguration: [AnyHashable: Any]?) -> Builder {
                configuration.proxyConfiguration = proxyConfiguration
                return self
            }

            /// Sets additional configuration attributes.
            /// This can be used to tweak internal features of the SDK.
            /// - Parameter additionalConfiguration: `[:]` by default.
            public func set(additionalConfiguration: [String: Any]) -> Builder {
                configuration.additionalConfiguration = additionalConfiguration
                return self
            }

            /// Sets data encryption to use for on-disk data persistency.
            /// - Parameter encryption: An encryption object complying with `DataEncryption` protocol.
            public func set(encryption: DataEncryption) -> Builder {
                configuration.encryption = encryption
                return self
            }

            /// Builds `Datadog.Configuration` object.
            public func build() -> Configuration {
                return configuration
            }
        }
    }
}
