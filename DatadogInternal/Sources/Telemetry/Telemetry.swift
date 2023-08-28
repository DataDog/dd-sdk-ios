/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct ConfigurationTelemetry: Equatable {
    public let batchSize: Int64?
    public let batchUploadFrequency: Int64?
    public let dartVersion: String?
    public let mobileVitalsUpdatePeriod: Int64?
    public let sessionSampleRate: Int64?
    public let telemetrySampleRate: Int64?
    public let traceSampleRate: Int64?
    public let trackBackgroundEvents: Bool?
    public let trackCrossPlatformLongTasks: Bool?
    public let trackErrors: Bool?
    public let trackFlutterPerformance: Bool?
    public let trackFrustrations: Bool?
    public let trackInteractions: Bool?
    public let trackLongTask: Bool?
    public let trackNativeLongTasks: Bool?
    public let trackNativeViews: Bool?
    public let trackNetworkRequests: Bool?
    public let trackViewsManually: Bool?
    public let useFirstPartyHosts: Bool?
    public let useLocalEncryption: Bool?
    public let useProxy: Bool?
    public let useTracing: Bool?
}

public enum TelemetryMessage {
    case debug(id: String, message: String, attributes: [String: Encodable]?)
    case error(id: String, message: String, kind: String?, stack: String?)
    case configuration(ConfigurationTelemetry)
    case metric(name: String, attributes: [String: Encodable])
}

/// The `Telemetry` protocol defines methods to collect debug information
/// and detect execution errors of the Datadog SDK.
public protocol Telemetry {
    /// Sends a Telemetry message.
    ///
    /// - Parameter telemetry: The telemtry message
    func send(telemetry: TelemetryMessage)
}

extension Telemetry {
    /// Collects debug information.
    ///
    /// - Parameters:
    ///   - id: Identity of the debug log, this can be used to prevent duplicates.
    ///   - message: The debug message.
    ///   - attributes: Custom attributes attached to the log (optional).
    public func debug(id: String, message: String, attributes: [String: Encodable]? = nil) {
        send(telemetry: .debug(id: id, message: message, attributes: attributes))
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - id: Identity of the debug log, this can be used to prevent duplicates.
    ///   - message: The error message.
    ///   - kind: The kind of error.
    ///   - stack: The stack trace.
    public func error(id: String, message: String, kind: String?, stack: String?) {
        send(telemetry: .error(id: id, message: message, kind: kind, stack: stack))
    }

    /// Report a Configuration Telemetry.
    ///
    /// The configuration can be partial, the telemetry should support accumulation of
    /// configuration for lazy initialization of the SDK.
    ///
    /// - Parameter configuration: The SDK configuration.
    public func report(configuration: ConfigurationTelemetry) {
        send(telemetry: .configuration(configuration))
    }

    /// Collects debug information.
    ///
    /// - Parameters:
    ///   - message: The debug message.
    ///   - attributes: Custom attributes attached to the log (optional).
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func debug(_ message: String, attributes: [String: Encodable]? = nil, file: String = #file, line: Int = #line) {
        debug(id: "\(file):\(line):\(message)", message: message, attributes: attributes)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - stack: The stack trace.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, kind: String? = nil, stack: String? = nil, file: String = #file, line: Int = #line) {
        error(id: "\(file):\(line):\(message)", message: message, kind: kind, stack: stack)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ error: DDError, file: String = #file, line: Int = #line) {
        self.error(error.message, kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, error: DDError, file: String = #file, line: Int = #line) {
        self.error("\(message) - \(error.message)", kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ error: Error, file: String = #file, line: Int = #line) {
        self.error(DDError(error: error), file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, error: Error, file: String = #file, line: Int = #line) {
        self.error(message, error: DDError(error: error), file: file, line: line)
    }

    /// Report a Configuration Telemetry.
    ///
    /// The configuration can be partial, the telemtry should support accumulation of
    /// configuration for lazy initialization of the SDK.
    public func configuration(
        batchSize: Int64? = nil,
        batchUploadFrequency: Int64? = nil,
        dartVersion: String? = nil,
        mobileVitalsUpdatePeriod: Int64? = nil,
        sessionSampleRate: Int64? = nil,
        telemetrySampleRate: Int64? = nil,
        traceSampleRate: Int64? = nil,
        trackBackgroundEvents: Bool? = nil,
        trackCrossPlatformLongTasks: Bool? = nil,
        trackErrors: Bool? = nil,
        trackFlutterPerformance: Bool? = nil,
        trackFrustrations: Bool? = nil,
        trackInteractions: Bool? = nil,
        trackLongTask: Bool? = nil,
        trackNativeLongTasks: Bool? = nil,
        trackNativeViews: Bool? = nil,
        trackNetworkRequests: Bool? = nil,
        trackViewsManually: Bool? = nil,
        useFirstPartyHosts: Bool? = nil,
        useLocalEncryption: Bool? = nil,
        useProxy: Bool? = nil,
        useTracing: Bool? = nil
    ) {
        self.report(configuration: .init(
            batchSize: batchSize,
            batchUploadFrequency: batchUploadFrequency,
            dartVersion: dartVersion,
            mobileVitalsUpdatePeriod: mobileVitalsUpdatePeriod,
            sessionSampleRate: sessionSampleRate,
            telemetrySampleRate: telemetrySampleRate,
            traceSampleRate: traceSampleRate,
            trackBackgroundEvents: trackBackgroundEvents,
            trackCrossPlatformLongTasks: trackCrossPlatformLongTasks,
            trackErrors: trackErrors,
            trackFlutterPerformance: trackFlutterPerformance,
            trackFrustrations: trackFrustrations,
            trackInteractions: trackInteractions,
            trackLongTask: trackLongTask,
            trackNativeLongTasks: trackNativeLongTasks,
            trackNativeViews: trackNativeViews,
            trackNetworkRequests: trackNetworkRequests,
            trackViewsManually: trackViewsManually,
            useFirstPartyHosts: useFirstPartyHosts,
            useLocalEncryption: useLocalEncryption,
            useProxy: useProxy,
            useTracing: useTracing
        ))
    }

    /// Collect metric value.
    ///
    /// Metrics are reported as debug telemetry. Unlike regular events, they are not subject to duplicates filtering and
    /// are get sampled with a different rate. Metric attributes are used to create facets for later querying and graphing.
    ///
    /// - Parameters:
    ///   - name: The name of this metric.
    ///   - attributes: Parameters associated with this metric.
    public func metric(name: String, attributes: [String: Encodable]) {
        send(telemetry: .metric(name: name, attributes: attributes))
    }
}

public struct NOPTelemetry: Telemetry {
    public init() { }
    /// no-op
    public func send(telemetry: TelemetryMessage) { }
}

internal struct CoreTelemetry: Telemetry {
    /// A weak core reference.
    private weak var core: DatadogCoreProtocol?

    /// Creates a Telemetry associated with a core instance.
    ///
    /// The `CoreTelemetry` keeps a weak reference
    /// to the provided core.
    ///
    /// - Parameter core: The core instance.
    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    /// Sends a Telemetry message.
    ///
    /// The Telemetry message will be transmitted on the message-bus
    /// of the core.
    ///
    /// - Parameter telemetry: The telemtry message.
    func send(telemetry: TelemetryMessage) {
        core?.send(message: .telemetry(telemetry))
    }
}

extension DatadogCoreProtocol {
    /// Telemetry endpoint.
    ///
    /// Use this property to report any telemetry event to the core.
    public var telemetry: Telemetry { CoreTelemetry(core: self) }
}

extension ConfigurationTelemetry {
    public func merged(with other: Self) -> Self {
        .init(
            batchSize: other.batchSize ?? batchSize,
            batchUploadFrequency: other.batchUploadFrequency ?? batchUploadFrequency,
            dartVersion: other.dartVersion ?? dartVersion,
            mobileVitalsUpdatePeriod: other.mobileVitalsUpdatePeriod ?? mobileVitalsUpdatePeriod,
            sessionSampleRate: other.sessionSampleRate ?? sessionSampleRate,
            telemetrySampleRate: other.telemetrySampleRate ?? telemetrySampleRate,
            traceSampleRate: other.traceSampleRate ?? traceSampleRate,
            trackBackgroundEvents: other.trackBackgroundEvents ?? trackBackgroundEvents,
            trackCrossPlatformLongTasks: other.trackCrossPlatformLongTasks ?? trackCrossPlatformLongTasks,
            trackErrors: other.trackErrors ?? trackErrors,
            trackFlutterPerformance: other.trackFlutterPerformance ?? trackFlutterPerformance,
            trackFrustrations: other.trackFrustrations ?? trackFrustrations,
            trackInteractions: other.trackInteractions ?? trackInteractions,
            trackLongTask: other.trackLongTask ?? trackLongTask,
            trackNativeLongTasks: other.trackNativeLongTasks ?? trackNativeLongTasks,
            trackNativeViews: other.trackNativeViews ?? trackNativeViews,
            trackNetworkRequests: other.trackNetworkRequests ?? trackNetworkRequests,
            trackViewsManually: other.trackViewsManually ?? trackViewsManually,
            useFirstPartyHosts: other.useFirstPartyHosts ?? useFirstPartyHosts,
            useLocalEncryption: other.useLocalEncryption ?? useLocalEncryption,
            useProxy: other.useProxy ?? useProxy,
            useTracing: other.useTracing ?? useTracing
        )
    }
}
