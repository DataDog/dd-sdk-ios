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

    /// Datadog Tracer configuration resolved with defaults coming from the other source.
    internal struct ResolvedConfiguration {
        internal let serviceName: String

        /// TODO: RUMM-409 Defaults should be resolved using `Datadog.instance`. I don't do it now, because the SDK-wide `serviceName`
        ///  must be first done on `master` branch, then merged to `tracing` and update here.
        init(tracerConfiguration: Configuration) {
            self.serviceName = tracerConfiguration.serviceName ?? "ios"
        }
    }
}
