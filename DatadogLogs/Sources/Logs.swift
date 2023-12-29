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
public enum Logs {
    /// The Logs general configuration.
    ///
    /// This configuration will be applied to all Logger instances.
    public struct Configuration {
        public typealias EventMapper = (LogEvent) -> LogEvent?
        /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
        ///
        /// The implementation should obtain a mutable version of the `LogEvent`, modify it and return it. Returning `nil` will result
        /// with dropping the Log event entirely, so it won't be send to Datadog.
        public var eventMapper: EventMapper?

        /// Overrides the custom server endpoint where Logs are sent.
        public var customEndpoint: URL?

        /// Overrides the date provider.
        internal var dateProvider: DateProvider = SystemDateProvider()

        /// Overrides the event mapper
        internal var _internalEventMapper: LogEventMapper? = nil

        /// Creates a Logs configuration object.
        ///
        /// - Parameters:
        ///   - eventMapper: The custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
        ///   - customEndpoint: Overrides the custom server endpoint where Logs are sent.
        public init(
            eventMapper: EventMapper? = nil,
            customEndpoint: URL? = nil
        ) {
            self.eventMapper = eventMapper
            self.customEndpoint = customEndpoint
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
        let logEventMapper = configuration._internalEventMapper ?? configuration.eventMapper.map(SyncLogEventMapper.init)

        let feature = LogsFeature(
            logEventMapper: logEventMapper,
            dateProvider: configuration.dateProvider,
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry
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
        type._internalEventMapper = mapper
    }
}
