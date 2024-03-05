/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public enum Metrics {
    /// The Metrics general configuration.
    public struct Configuration {
        /// Either the API key or a regular client token
        /// For metrics reporting API key is needed
        public var apiKey: String
        /// Overrides the custom server endpoint where Metrics are sent.
        public var customEndpoint: URL?

        /// Overrides the date provider.
        internal var dateProvider: DateProvider = SystemDateProvider()

        /// Creates a Metrics configuration object.
        ///
        /// - Parameters:
        ///   - customEndpoint: Overrides the custom server endpoint where Metrics are sent.
        public init(
            apiKey: String,
            customEndpoint: URL? = nil
        ) {
            self.apiKey = apiKey
            self.customEndpoint = customEndpoint
        }
    }
    
    public static func enable(with configuration: Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        let feature = MetricFeature(
            apiKey: configuration.apiKey,
            recorder: Recorder(core: core),
            subscriber: DatadogMetricSubscriber(core: core),
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )

        do {
            try core.register(feature: feature)
        } catch let error {
            consolePrint("\(error)", .error)
       }
    }
}

#if canImport(MetricKit)
import MetricKit

extension Metrics {
    static public func send(_ payloads: [MXMetricPayload], to core: DatadogCoreProtocol = CoreRegistry.default) {
        core.get(feature: MetricFeature.self)?.subscriber.didReceive(payloads)
    }
}

#endif
