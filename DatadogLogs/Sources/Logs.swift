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
        with configuration: Logs.Configuration = .init(),
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            try runOnMainThreadSync {
                try enableOrThrow(with: configuration, in: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    internal static func enableOrThrow(
        with configuration: Logs.Configuration, in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `Logs.enable(with:)`."
            )
        }

        let logEventMapper = configuration._internalEventMapper ?? configuration.eventMapper.map(SyncLogEventMapper.init)

        let feature = LogsFeature(
            logEventMapper: logEventMapper,
            dateProvider: configuration.dateProvider,
            customIntakeURL: configuration.customEndpoint,
            telemetry: core.telemetry,
            backtraceReporter: core.backtraceReporter
        )

        try core.register(feature: feature)
    }

    /// Adds a custom attribute to all future logs sent by any logger created from the provided Core.
    /// - Parameters:
    ///   - key: the attribute key. See `AttributeKey` documentation for information on nesting attributes with dot `.` syntax.
    ///   - value: the attribute value that conforms to `Encodable`. See `AttributeValue` documentation
    ///     for information on nested encoding containers limitation.
    ///   - core: the `DatadogCoreProtocol` to add the attribute to.
    public static func addAttribute(forKey key: AttributeKey, value: AttributeValue, in core: DatadogCoreProtocol = CoreRegistry.default) {
        guard let feature = core.get(feature: LogsFeature.self) else {
            return
        }
        feature.attributes.addAttribute(key: key, value: value)
        sendAttributesChanged(for: feature, in: core)
    }

    /// Removes the custom attribute from all future logs sent any logger created from the provided Core.
    ///
    /// Previous logs won't lose this attribute if sent prior to this call.
    /// - Parameters:
    ///   - key: the key of an attribute that will be removed.
    ///   - core: the `DatadogCoreProtocol` to remove the attribute from.
    public static func removeAttribute(forKey key: AttributeKey, in core: DatadogCoreProtocol = CoreRegistry.default) {
        guard let feature = core.get(feature: LogsFeature.self) else {
            return
        }
        feature.attributes.removeAttribute(forKey: key)
        sendAttributesChanged(for: feature, in: core)
    }

    private static func sendAttributesChanged(for feature: LogsFeature, in core: DatadogCoreProtocol) {
        core.send(
            message: .payload(LogEventAttributes(
                attributes: feature.attributes.getAttributes()
            ))
        )
    }
}

extension Logs {
    /// Attributes that can be added to logs that have special properies in Datadog.
    public struct Attributes {
        /// Add a custom fingerprint to the error in this log. Requires that the log is supplied with an Error.
        /// The value of this attribute must be a `String`.
        public static let errorFingerprint = "_dd.error.fingerprint"
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
