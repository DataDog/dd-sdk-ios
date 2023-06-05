/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension Tracer {
    /// Datadog Tracer configuration.
    public struct Configuration {
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

        /// The sampling rate for Traces, as a Float between 0 and 100. Defautl is 100.
        public var samplingRate: Float

        /// Initializes the Datadog Tracer configuration.
        /// - Parameter serviceName: the service name that will appear in traces (if not provided or `nil`, the SDK default `serviceName` will be used).
        /// - Parameter sendNetworkInfo: adds network connection info to every span and span logs (`false` by default).
        /// - Parameter bundleWithRUM: enables the tracing integration with RUM. If enabled all the Spans will be enriched with the current RUM View information and
        /// it will be possible to see all the Spans sent during a specific View lifespan in the RUM Explorer (`true` by default).
        /// - Parameter globalTags: sets global tags for all Spans (`nil` by default).
        public init(
            serviceName: String? = nil,
            sendNetworkInfo: Bool = false,
            bundleWithRUM: Bool = true,
            samplingRate: Float = 100,
            globalTags: [String: Encodable]? = nil
        ) {
            self.serviceName = serviceName
            self.sendNetworkInfo = sendNetworkInfo
            self.bundleWithRUM = bundleWithRUM
            self.samplingRate = samplingRate
            self.globalTags = globalTags
        }
    }
}
