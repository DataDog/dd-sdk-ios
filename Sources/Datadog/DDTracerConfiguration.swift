/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

extension DDTracer {
    /// Datadog Tracer configuration.
    public struct Configuration {
        /// The service name that will appear in traces (if not provided or `nil`, the SDK default `serviceName` will be used).
        public var serviceName: String?

        /// Initializes the Datadog Tracer configuration.
        /// - Parameter serviceName: the service name that will appear in traces (if not provided or `nil`, the SDK default `serviceName` will be used).
        public init(serviceName: String? = nil) {
            self.serviceName = serviceName
        }
    }
}
