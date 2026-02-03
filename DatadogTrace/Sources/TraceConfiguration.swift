/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// Export `URLSessionInstrumentation` elements to be available with `import DatadogTrace`:
// swiftlint:disable duplicate_imports
@_exported import enum DatadogInternal.URLSessionInstrumentation

@_exported import class DatadogInternal.HTTPHeadersWriter
@_exported import class DatadogInternal.B3HTTPHeadersWriter
@_exported import class DatadogInternal.W3CHTTPHeadersWriter
@_exported import enum DatadogInternal.TraceContextInjection
@_exported import enum DatadogInternal.TracingHeaderType
// swiftlint:enable duplicate_imports

extension Trace {
    /// Trace feature configuration.
    public struct Configuration: SampledTelemetry {
        public typealias EventMapper = (SpanEvent) -> SpanEvent

        /// The sampling rate for spans created with the default tracer.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no spans will be collected.
        ///
        /// Default: `100.0`.
        public var sampleRate: SampleRate

        /// The `service` value for spans.
        ///
        /// If not specified, the SDK default `service` will be used.
        public var service: String?

        /// Global tags associated with each span created with the default tracer.
        public var tags: [String: Encodable]?

        /// The configuration for automatic network requests tracing.
        ///
        /// RUM resources tracking requires enabling `URLSessionInstrumentation`. See
        /// `URLSessionInstrumentation.enable(with:)`.
        ///
        /// Note: Automatic RUM resources tracking involves swizzling the `URLSession`, `URLSessionTask` and
        /// `URLSessionDataDelegate` methods.
        ///
        /// Default: `nil` - which means automatic tracing is not enabled by default.
        public var urlSessionTracking: URLSessionTracking?

        /// Enables the integration of traces with RUM.
        ///
        /// When enabled, all spans will be enriched with the current RUM view information.
        ///
        /// Default: `true`.
        public var bundleWithRumEnabled: Bool

        /// Enriches traces with network connection information.
        ///
        /// This includes reachability status, connection type, mobile carrier name, and more, which will be added to every span and span log.
        ///
        /// Default: `false`
        public var networkInfoEnabled: Bool

        /// Custom mapper for span events.
        ///
        /// It can be used to modify span events before they are sent. The implementation of the mapper should
        /// obtain a mutable copy of `SpanEvent`, modify it, and return it. Keep the implementation fast
        /// and do not make any assumptions on the thread used to run it.
        ///
        /// Default: `nil`.
        public var eventMapper: EventMapper?

        /// Custom server url for sending traces.
        ///
        /// Default: `nil`.
        public var customEndpoint: URL?

        // MARK: - Nested Types

        /// Configuration of automatic network requests tracing.
        public struct URLSessionTracking {
            /// Determines distributed tracing configuration for particular first-party hosts.
            ///
            /// Each request is classified as first-party or third-party based on the first-party hosts configured, i.e.:
            /// * If "example.com" is defined as a first-party host:
            ///     - First-party URL examples: https://example.com/ and https://api.example.com/v2/users
            ///     - Third-party URL example: https://foo.com/
            /// * If "api.example.com" is defined as a first-party host:
            ///     - First-party URL examples: https://api.example.com/ and https://api.example.com/v2/users
            ///     - Third-party URL examples: https://example.com/ and https://foo.com/
            ///
            /// A trace will be created for each first-party request by injecting HTTP trace headers and creating an APM span.
            /// If your backend is also instrumented with Datadog, you will see the full trace (app → backend).
            public var firstPartyHostsTracing: FirstPartyHostsTracing

            /// Defines configuration for first-party hosts in distributed tracing.
            public enum FirstPartyHostsTracing {
                /// Trace the specified hosts using Datadog and W3C `tracecontext` tracing headers.
                ///
                /// - Parameters:
                ///   - hosts: The set of hosts to inject tracing headers. Note: Hosts must not include the "http(s)://" prefix.
                ///   - sampleRate: The sampling rate for tracing. Must be a value between `0.0` and `100.0`. Default: `100`.
                ///   - traceControlInjection: The strategy for injecting trace context into requests. Default: `.sampled`.
                case trace(
                    hosts: Set<String>,
                    sampleRate: Float = .maxSampleRate,
                    traceControlInjection: TraceContextInjection = .sampled
                )

                /// Trace given hosts with using custom tracing headers.
                ///
                /// - `hostsWithHeaders` - Dictionary of hosts and tracing header types to use. Note: Hosts must not include "http(s)://" prefix.
                /// - `sampleRate` - The sampling rate for tracing. Must be a value between `0.0` and `100.0`. Default: `100`.
                ///   - traceControlInjection: The strategy for injecting trace context into requests. Default: `.sampled`.
                case traceWithHeaders(
                    hostsWithHeaders: [String: Set<TracingHeaderType>],
                    sampleRate: Float = .maxSampleRate,
                    traceControlInjection: TraceContextInjection = .sampled
                )
            }

            /// Configuration for automatic network requests tracing.
            /// - Parameters:
            ///   - firstPartyHostsTracing: Distributed tracing configuration for particular first-party hosts.
            public init(firstPartyHostsTracing: FirstPartyHostsTracing) {
                self.firstPartyHostsTracing = firstPartyHostsTracing
            }
        }

        // MARK: - Internal

        internal var traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator()
        internal var spanIDGenerator: SpanIDGenerator = DefaultSpanIDGenerator()
        internal var dateProvider: DateProvider = SystemDateProvider()
        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

        /// Creates Trace configuration.
        /// - Parameters:
        ///   - sampleRate: The sampling rate for spans created with the default tracer.
        ///   - service: The `service` value for spans.
        ///   - tags: Global tags associated with each span created with the default tracer.
        ///   - urlSessionTracking: The configuration for automatic network requests tracing.
        ///   - bundleWithRumEnabled: Determines if traces should be enriched with RUM information.
        ///   - networkInfoEnabled: Determines if traces should be enriched with network connection information.
        ///   - eventMapper: Custom mapper for span events.
        ///   - customEndpoint: Custom server url for sending traces.
        public init(
            sampleRate: SampleRate = .maxSampleRate,
            service: String? = nil,
            tags: [String: Encodable]? = nil,
            urlSessionTracking: URLSessionTracking? = nil,
            bundleWithRumEnabled: Bool = true,
            networkInfoEnabled: Bool = false,
            eventMapper: EventMapper? = nil,
            customEndpoint: URL? = nil
        ) {
            self.sampleRate = sampleRate
            self.service = service
            self.tags = tags
            self.urlSessionTracking = urlSessionTracking
            self.bundleWithRumEnabled = bundleWithRumEnabled
            self.networkInfoEnabled = networkInfoEnabled
            self.eventMapper = eventMapper
            self.customEndpoint = customEndpoint
        }
    }
}
