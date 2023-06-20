/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogLogs

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
        private(set) var loggingEnabled: Bool
        private(set) var tracingEnabled: Bool
        private(set) var serverDateProvider: ServerDateProvider?

        /// If `DatadogSite` is set, it will override `logsEndpoint` and `tracesEndpoint`.
        private(set) var datadogEndpoint: DatadogSite
        /// If `customLogsEndpoint` is set, it will override logs endpoint value configured with `logsEndpoint` and `DatadogSite`.
        private(set) var customLogsEndpoint: URL?

        private(set) var serviceName: String?
        private(set) var firstPartyHosts: FirstPartyHosts?
        var logEventMapper: LogEventMapper?
        private(set) var loggingSamplingRate: Float
        private(set) var tracingSamplingRate: Float
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
                    loggingEnabled: true,
                    tracingEnabled: true,
                    // While `.set(<feature>Endpoint:)` APIs are deprecated, the `datadogEndpoint` default must be `nil`,
                    // so we know the clear user's intent to override deprecated values.
                    datadogEndpoint: .us1,
                    customLogsEndpoint: nil,
                    serviceName: nil,
                    firstPartyHosts: nil,
                    loggingSamplingRate: 100.0,
                    tracingSamplingRate: 20.0,
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

            /// Sets the custom server endpoint where Logs are sent.
            ///
            /// - Parameter endpoint: server endpoint (not set by default)
            public func set(customLogsEndpoint: URL) -> Builder {
                configuration.customLogsEndpoint = customLogsEndpoint
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

            // MARK: - Logging Configuration

            /// Enables or disables the logging feature.
            ///
            /// This option is meant to opt-out from using Datadog Logging entirely, no matter of your environment or build configuration. If you need to
            /// disable logging only for certain scenarios (e.g. in `DEBUG` build configuration), use `sendLogsToDatadog(false)` available
            /// on `Logger.Builder`.
            ///
            /// If `enableLogging(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the logging feature. This will give you additional performance optimization if you only use RUM or tracing.
            ///
            /// **NOTE**: If you use logging for tracing (`span.log(fields:)`) keep the logging feature enabled. Otherwise the logs
            /// you send for `span` objects won't be delivered to Datadog.
            ///
            /// - Parameter enabled: `true` by default
            public func enableLogging(_ enabled: Bool) -> Builder {
                configuration.loggingEnabled = enabled
                return self
            }

            /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
            /// - Parameter mapper: the closure taking `LogEvent` as input and expecting `LogEvent` as output.
            /// The implementation should obtain a mutable version of the `LogEvent`, modify it and return it. Returning `nil` will result
            /// with dropping the Log event entirely, so it won't be send to Datadog.
            public func setLogEventMapper(_ mapper: @escaping (LogEvent) -> LogEvent?) -> Builder {
                configuration.logEventMapper = SyncLogEventMapper(mapper)
                return self
            }

            /// Sets the sampling rate for logging.
            ///
            /// - Parameter loggingSamplingRate: the sampling rate must be a value between `0.0` and `100.0`. A value of `0.0`
            /// means no logs will be processed, `100.0` means all logs will be processed.
            /// (by default sampling is disabled, meaning that all logs are being processed).
            public func set(loggingSamplingRate: Float) -> Builder {
                configuration.loggingSamplingRate = loggingSamplingRate
                return self
            }

            // MARK: - Tracing Configuration

            /// Enables or disables the tracing feature.
            ///
            /// This option is meant to opt-out from using Datadog Tracing entirely, no matter of your environment or build configuration. If you need to
            /// disable tracing only for certain scenarios (e.g. in `DEBUG` build configuration), do not initialize the tracer `DatadogTracer.initialize`.
            ///
            /// If `enableTracing(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the tracing feature. This will give you additional performance optimization if you only use RUM or logging.
            ///
            /// - Parameter enabled: `true` by default
            public func enableTracing(_ enabled: Bool) -> Builder {
                configuration.tracingEnabled = enabled
                return self
            }

            /// Configures network requests monitoring for Tracing and RUM features. **Must be used together with** `DDURLSessionDelegate` set as the `URLSession` delegate.
            @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
            public func set(tracedHosts: Set<String>) -> Builder {
                return track(firstPartyHosts: tracedHosts)
            }

            @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
            public func track(firstPartyHosts: Set<String>) -> Builder {
                return trackURLSession(firstPartyHosts: firstPartyHosts)
            }

            /// Configures network requests monitoring for Tracing and RUM features. **It must be used together with** `DDURLSessionDelegate` set as the `URLSession` delegate.
            ///
            /// If set, the SDK will intercept all network requests made by `URLSession` instances which use `DDURLSessionDelegate`.
            ///
            /// Each request will be classified as 1st- or 3rd-party based on the host comparison, i.e.:
            /// * if `firstPartyHosts` is `["example.com"]`:
            ///     - 1st-party URL examples: https://example.com/, https://api.example.com/v2/users
            ///     - 3rd-party URL examples: https://foo.com/
            /// * if `firstPartyHosts` is `["api.example.com"]`:
            ///     - 1st-party URL examples: https://api.example.com/, https://api.example.com/v2/users
            ///     - 3rd-party URL examples: https://example.com/, https://foo.com/
            ///
            /// If RUM feature is enabled, the SDK will send RUM Resources for all intercepted requests.
            ///
            /// If Tracing feature is enabled, the SDK will send tracing Span for each 1st-party request. It will also add extra HTTP headers to further propagate the trace - it means that
            /// if your backend is instrumented with Datadog agent you will see the full trace (e.g.: client → server → database) in your dashboard, thanks to Datadog Distributed Tracing.
            ///
            /// For more control over the kind of headers used for Distributed Tracing, see `trackURLSession(firstPartyHostsWithHeaderTypes:)`.
            ///
            /// If both RUM and Tracing features are enabled, the SDK will be sending RUM Resources for 1st- and 3rd-party requests and tracing Spans for 1st-parties.
            ///
            /// Until `trackURLSession()` is called, network requests monitoring is disabled.
            ///
            /// **NOTE 1:** Enabling this option will install swizzlings on some methods of the `URLSession`. Refer to `URLSessionSwizzler.swift`
            /// for implementation details.
            ///
            /// **NOTE 2:** The `URLSession` instrumentation will NOT work without using `DDURLSessionDelegate`.
            ///
            /// **NOTE 3:** If used simultaneously with `trackURLSession(firstPartyHostsWithHeaderTypes:)` it will merge first party hosts provided in both.
            ///
            /// - Parameter firstPartyHosts: empty set by default
            public func trackURLSession(firstPartyHosts: Set<String> = []) -> Builder {
                return trackURLSession(firstPartyHostsWithHeaderTypes: firstPartyHosts.reduce(into: [:], { partialResult, host in
                    partialResult[host] = [.datadog]
                }))
            }

            /// The `trackURLSession(firstPartyHostsWithHeaderTypes:)` function is an alternate version of `trackURLSession(firstPartyHosts:)`
            /// that allows for more fine-grained control over the HTTP headers used for Distributed Tracing.
            ///
            /// Configures network requests monitoring for Tracing and RUM features. **It must be used together with** `DDURLSessionDelegate` set as the `URLSession` delegate.
            ///
            /// If set, the SDK will intercept all network requests made by `URLSession` instances which use `DDURLSessionDelegate`.
            ///
            /// Each request will be classified as 1st- or 3rd-party based on the host comparison, i.e.:
            /// * if `firstPartyHostsWithHeaderTypes` is `["example.com": [.datadog]]`:
            ///     - 1st-party URL examples: https://example.com/, https://api.example.com/v2/users
            ///     - 3rd-party URL examples: https://foo.com/
            /// * if `firstPartyHostsWithHeaderTypes` is `["api.example.com": [.datadog]]]`:
            ///     - 1st-party URL examples: https://api.example.com/, https://api.example.com/v2/users
            ///     - 3rd-party URL examples: https://example.com/, https://foo.com/
            ///
            /// If RUM feature is enabled, the SDK will send RUM Resources for all intercepted requests.
            ///
            /// If Tracing feature is enabled, the SDK will send tracing Span for each 1st-party request. It will also add extra HTTP headers to further propagate the trace - it means that
            /// if your backend is instrumented with Datadog agent you will see the full trace (e.g.: client → server → database) in your dashboard, thanks to Datadog Distributed Tracing.
            ///
            /// If both RUM and Tracing features are enabled, the SDK will be sending RUM Resources for 1st- and 3rd-party requests and tracing Spans for 1st-parties.
            ///
            /// Until `trackURLSession()` is called, network requests monitoring is disabled.
            ///
            /// **NOTE 1:** Enabling this option will install swizzlings on some methods of the `URLSession`. Refer to `URLSessionSwizzler.swift`
            /// for implementation details.
            ///
            /// **NOTE 2:** The `URLSession` instrumentation will NOT work without using `DDURLSessionDelegate`.
            ///
            /// **NOTE 3:** If used simultaneously with `trackURLSession(firstPartyHosts:)` it will merge first party hosts provided in both.
            ///
            /// - Parameter firstPartyHostsWithHeaderTypes: Dictionary used to classify network requests as 1st-party
            /// and determine the HTTP header types to use for Distributed Tracing. Key is a host and value is a set of tracing header types.
            public func trackURLSession(firstPartyHostsWithHeaderTypes: [String: Set<TracingHeaderType>]) -> Builder {
                configuration.firstPartyHosts += FirstPartyHosts(firstPartyHostsWithHeaderTypes)
                return self
            }

            /// Sets the sampling rate for APM traces created for auto-instrumented `URLSession` requests.
            ///
            /// - Parameter tracingSamplingRate: the sampling rate must be a value between `0.0` and `100.0`. A value of `0.0`
            /// means no trace will be kept, `100.0` means all traces will be kept (default value is `20.0`).
            public func set(tracingSamplingRate: Float) -> Builder {
                configuration.tracingSamplingRate = tracingSamplingRate
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
