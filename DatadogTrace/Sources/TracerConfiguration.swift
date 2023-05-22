/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension DatadogTracer {
    /// Datadog Tracer configuration.
    public struct Configuration {
        /// The custom intake endpoint.
        public var customIntakeURL: URL? = nil

        /// The service name that will appear in traces (if not provided or `nil`, the SDK default `serviceName` will be used).
        public var serviceName: String?

        /// Enriches traces with network connection info.
        /// This means: reachability status, connection type, mobile carrier name and many more will be added to every span and span logs.
        /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
        /// - Parameter enabled: `false` by default
        public var sendNetworkInfo: Bool

        /// Tags that will be added to all spans created by the tracer.
        public var globalTags: [String: Encodable]?

        /// Enables the traces integration with RUM.
        /// If enabled all the spans will be enriched with the current RUM View information and
        /// it will be possible to see all the spans produced during a specific View lifespan in the RUM Explorer.
        /// - Parameter enabled: `true` by default
        public var bundleWithRUM: Bool

        /// The sampling rate for Traces, as a Float between 0 and 100.
        public var samplingRate: Float

        /// Span events mapper configured by the user, `nil` if not set.
        public var spanEventMapper: SpanEventMapper?

        /// Initializes the Datadog Tracer configuration.
        /// - Parameter serviceName: the service name that will appear in traces (if not provided or `nil`, the SDK default `serviceName` will be used).
        /// - Parameter sendNetworkInfo: adds network connection info to every span and span logs (`false` by default).
        /// - Parameter bundleWithRUM: enables the tracing integration with RUM. If enabled all the Spans will be enriched with the current RUM View information and
        /// it will be possible to see all the Spans sent during a specific View lifespan in the RUM Explorer (`true` by default).
        /// - Parameter globalTags: sets global tags for all Spans (`nil` by default).
        /// - Parameter samplingRate: sets sampling rate for Traces, as a Float between 0 and 100. (`100` by default).
        public init(
            serviceName: String? = nil,
            sendNetworkInfo: Bool = false,
            bundleWithRUM: Bool = true,
            samplingRate: Float = 100,
            globalTags: [String: Encodable]? = nil,
            customIntakeURL: URL? = nil,
            spanEventMapper: SpanEventMapper? = nil
        ) {
            self.serviceName = serviceName
            self.sendNetworkInfo = sendNetworkInfo
            self.bundleWithRUM = bundleWithRUM
            self.samplingRate = samplingRate
            self.globalTags = globalTags
            self.customIntakeURL = customIntakeURL
            self.spanEventMapper = spanEventMapper
        }
    }

    /// Datadog Distributed Tracing configuration.
    public struct DistributedTracingConfiguration {
        public var firstPartyHosts: [String: Set<TracingHeaderType>]
        public var tracingSamplingRate: Float

        /// Configures network requests monitoring for Distributed Tracing. **It must be used together with** `DatadogURLSessionDelegate` set as the `URLSession` delegate.
        ///
        /// **Do not use this configuration if you intend to use RUM, configure Distributed Tracing in RUM instead**
        ///
        /// If set, Datadog SDK will intercept all network requests made by `URLSession` instances which use `DatadogURLSessionDelegate`.
        ///
        /// Each request will be classified as 1st- or 3rd-party based on the host comparison, i.e.:
        /// * if `firstPartyHosts` is `["example.com"]`:
        ///     - 1st-party URL examples: https://example.com/, https://api.example.com/v2/users
        ///     - 3rd-party URL examples: https://foo.com/
        /// * if `firstPartyHosts` is `["api.example.com"]`:
        ///     - 1st-party URL examples: https://api.example.com/, https://api.example.com/v2/users
        ///     - 3rd-party URL examples: https://example.com/, https://foo.com/
        ///
        /// The `DatadogTracer` will send tracing Span for each 1st-party request. It will also add extra HTTP headers to further propagate the trace - it means that
        /// if your backend is instrumented with Datadog agent you will see the full trace (e.g.: client → server → database) in your dashboard, thanks to Datadog Distributed Tracing.
        ///
        /// **NOTE 1:** Enabling this option will install swizzlings on some methods of the `URLSession`. Refer to `URLSessionSwizzler.swift`
        /// for implementation details.
        ///
        /// **NOTE 2:** The `URLSession` instrumentation will NOT work without using `DatadogURLSessionDelegate`.
        ///
        /// - Parameters:
        ///   - firstPartyHosts: empty set by default
        ///   - tracingSamplingRate: The Tracing sampling rate.
        public init(
            firstPartyHosts: Set<String> = [],
            tracingSamplingRate: Float = 20.0
        ) {
            self.firstPartyHosts = firstPartyHosts.reduce(into: [:]) { $0[$1] = [.datadog] }
            self.tracingSamplingRate = tracingSamplingRate
        }

        /// Configures network requests monitoring for Tracing and RUM features. **It must be used together with** `DatadogURLSessionDelegate` set as the `URLSession` delegate.
        ///
        /// **Do not use this configuration if you intend to use RUM, configure Distributed Tracing in RUM instead**
        ///
        /// If set, Datadog SDK will intercept all network requests made by `URLSession` instances which use `DatadogURLSessionDelegate`.
        ///
        /// Each request will be classified as 1st- or 3rd-party based on the host comparison, i.e.:
        /// * if `firstPartyHostsWithHeaderTypes` is `["example.com": [.datadog]]`:
        ///     - 1st-party URL examples: https://example.com/, https://api.example.com/v2/users
        ///     - 3rd-party URL examples: https://foo.com/
        /// * if `firstPartyHostsWithHeaderTypes` is `["api.example.com": [.datadog]]]`:
        ///     - 1st-party URL examples: https://api.example.com/, https://api.example.com/v2/users
        ///     - 3rd-party URL examples: https://example.com/, https://foo.com/
        ///
        /// The `DatadogTracer` will send tracing Span for each 1st-party request. It will also add extra HTTP headers to further propagate the trace - it means that
        /// if your backend is instrumented with Datadog agent you will see the full trace (e.g.: client → server → database) in your dashboard, thanks to Datadog Distributed Tracing.
        ///
        /// **NOTE 1:** Enabling this option will install swizzlings on some methods of the `URLSession`. Refer to `URLSessionSwizzler.swift`
        /// for implementation details.
        ///
        /// **NOTE 2:** The `URLSession` instrumentation will NOT work without using `DatadogURLSessionDelegate`.
        ///
        /// - Parameters:
        ///   - firstPartyHostsWithHeaderTypes: Dictionary used to classify network requests as 1st-party and determine the
        ///   HTTP header types to use for Distributed Tracing. Key is a host and value is a set of tracing header types.
        ///   - tracingSamplingRate: The Tracing sampling rate.
        /// - Parameter firstPartyHostsWithHeaderTypes: Dictionary used to classify network requests as 1st-party
        public init(
            firstPartyHostsWithHeaderTypes: [String: Set<TracingHeaderType>],
            tracingSamplingRate: Float = 20.0
        ) {
            self.firstPartyHosts = firstPartyHostsWithHeaderTypes
            self.tracingSamplingRate = tracingSamplingRate
        }
    }
}
