/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// iOS Log Collection
///
/// Send logs to Datadog from your iOS applications with Datadog’s dd-sdk-ios client-side logging library and leverage the following features:
/// - Log to Datadog in JSON format natively.
/// - Use default and add custom attributes to each log sent.
/// - Record real client IP addresses and User-Agents.
/// - Leverage optimized network usage with automatic bulk posts.
public struct Logs {
    /// The Logs general configuration.
    ///
    /// This configuration will be applied to all Logger instances.
    public struct Configuration {
        public typealias EventMapperClosure = (LogEvent) -> LogEvent?
        /// Sets the sampling rate for logging.
        ///
        /// The sampling rate must be a value between `0` and `100`. A value of `0` means no logs will be processed, `100`
        /// means all logs will be processed.
        ///
        /// By default sampling is disabled, meaning that all logs are being processed).
        public var sampleRate: Float

        /// Overrides the custom server endpoint where Logs are sent.
        public var customEndpoint: URL?

        /// Overrides the main bundle instance.
        public var bundle: Bundle = .main

        /// Overrides the current process info.
        internal var processInfo: ProcessInfo = .processInfo

        /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
        ///
        /// - Parameter mapper: the closure taking `LogEvent` as input and expecting `LogEvent` as output.
        /// The implementation should obtain a mutable version of the `LogEvent`, modify it and return it. Returning `nil` will result
        /// with dropping the Log event entirely, so it won't be send to Datadog.
        public mutating func eventMapper(_ mapper: @escaping EventMapperClosure) {
            self.mapper = SyncLogEventMapper(mapper)
        }

        /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
        ///
        /// The implementation should obtain a mutable version of the `LogEvent`, modify it and return it. Returning `nil` will result
        /// with dropping the Log event entirely, so it won't be send to Datadog.
        internal var mapper: LogEventMapper?

        /// Creates a Logs configuration object.
        ///
        /// - Parameters:
        ///   - eventMapper: The custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
        ///   - sampleRate: The sample rate for logging.
        ///   - sampleRate: Overrides the custom server endpoint where Logs are sent.
        ///   - bundle: Overrides the main bundle instance.
        public init(
            eventMapper: EventMapperClosure? = nil,
            sampleRate: Float = 100,
            customEndpoint: URL? = nil,
            bundle: Bundle = .main
        ) {
            self.mapper = eventMapper.map(SyncLogEventMapper.init)
            self.sampleRate = sampleRate
            self.customEndpoint = customEndpoint
            self.bundle = bundle
        }
    }

    /// Enables the Datadog Logs feature.
    ///
    /// - Parameters:
    ///   - configuration: The Logs configuration.
    ///   - core: The instance of Datadog SDK to enable Logs in (global instance by default).
    public static func enable(
        with configuration: Configuration = .init(),
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        let applicationBundleIdentifier = configuration.bundle.bundleIdentifier ?? "unknown"
        let debug = configuration.processInfo.arguments.contains(LaunchArguments.Debug)
        let feature = LogsFeature(
            logEventMapper: configuration.mapper,
            dateProvider: SystemDateProvider(),
            applicationBundleIdentifier: applicationBundleIdentifier,
            remoteLoggingSampler: Sampler(samplingRate: debug ? 100 : configuration.sampleRate),
            customIntakeURL: configuration.customEndpoint
        )

        do {
            try core.register(feature: feature)
        } catch {
            consolePrint("\(error)")
        }
    }
}

extension Logs.Configuration: InternalExtended { }
extension InternalExtension where ExtendedType == Logs.Configuration {
    /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are sent to Datadog.
    ///
    /// - Parameter mapper: the mapper taking `LogEvent` as input and invoke callback closure with modifier `LogEvent`.
    public mutating func setLogEventMapper(_ mapper: LogEventMapper) {
        type.mapper = mapper
    }
}
