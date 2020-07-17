/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

        /// Tags that will be added to all new spans created by the tracer.
        public var globalTags: [String: Encodable]?

        /// Initializes the Datadog Tracer configuration.
        /// - Parameter serviceName: the service name that will appear in traces (if not provided or `nil`, the SDK default `serviceName` will be used).
        /// - Parameter sendNetworkInfo: adds network connection info to every span and span logs (`false` by default).
        public init(
            serviceName: String? = nil,
            sendNetworkInfo: Bool = false,
            globalTags: [String: Encodable]? = nil
        ) {
            self.serviceName = serviceName
            self.sendNetworkInfo = sendNetworkInfo
            self.globalTags = globalTags
        }
    }
}
