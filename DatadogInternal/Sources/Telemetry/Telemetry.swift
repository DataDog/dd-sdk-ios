/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct ConfigurationTelemetry: Equatable {
    public let actionNameAttribute: String?
    public let allowFallbackToLocalStorage: Bool?
    public let allowUntrustedEvents: Bool?
    public let backgroundTasksEnabled: Bool?
    public let batchProcessingLevel: Int64?
    public let batchSize: Int64?
    public let batchUploadFrequency: Int64?
    public let dartVersion: String?
    public let defaultPrivacyLevel: String?
    public let forwardErrorsToLogs: Bool?
    public let initializationType: String?
    public let mobileVitalsUpdatePeriod: Int64?
    public let premiumSampleRate: Int64?
    public let reactNativeVersion: String?
    public let reactVersion: String?
    public let replaySampleRate: Int64?
    public let sessionReplaySampleRate: Int64?
    public let sessionSampleRate: Int64?
    public let silentMultipleInit: Bool?
    public let startSessionReplayRecordingManually: Bool?
    public let telemetryConfigurationSampleRate: Int64?
    public let telemetrySampleRate: Int64?
    public let traceSampleRate: Int64?
    public let trackBackgroundEvents: Bool?
    public let trackCrossPlatformLongTasks: Bool?
    public let trackErrors: Bool?
    public let trackFlutterPerformance: Bool?
    public let trackFrustrations: Bool?
    public let trackInteractions: Bool?
    public let trackLongTask: Bool?
    public let trackNativeErrors: Bool?
    public let trackNativeLongTasks: Bool?
    public let trackNativeViews: Bool?
    public let trackNetworkRequests: Bool?
    public let trackResources: Bool?
    public let trackSessionAcrossSubdomains: Bool?
    public let trackUserInteractions: Bool?
    public let trackViewsManually: Bool?
    public let useAllowedTracingOrigins: Bool?
    public let useAllowedTracingUrls: Bool?
    public let useBeforeSend: Bool?
    public let useCrossSiteSessionCookie: Bool?
    public let useExcludedActivityUrls: Bool?
    public let useFirstPartyHosts: Bool?
    public let useLocalEncryption: Bool?
    public let useProxy: Bool?
    public let useSecureSessionCookie: Bool?
    public let useTracing: Bool?
    public let useWorkerUrl: Bool?
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

/// List of error IDs sent in this process with `Telemetry.errorOnce()` API.
internal var onceErrorIDs: Set<String> = []

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
    public func debug(_ message: String, attributes: [String: Encodable]? = nil, file: StaticString = #fileID, line: UInt = #line) {
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
    public func error(_ message: String, kind: String? = nil, stack: String? = nil, file: StaticString = #fileID, line: UInt = #line) {
        error(id: "\(file):\(line):\(message)", message: message, kind: kind, stack: stack)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ error: DDError, file: StaticString = #fileID, line: UInt = #line) {
        self.error(error.message, kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, error: DDError, file: StaticString = #fileID, line: UInt = #line) {
        self.error("\(message) - \(error.message)", kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ error: Error, file: StaticString = #fileID, line: UInt = #line) {
        self.error(DDError(error: error), file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, error: Error, file: StaticString = #fileID, line: UInt = #line) {
        self.error(message, error: DDError(error: error), file: file, line: line)
    }

    /// Collects execution errors only once per process.
    ///
    /// In certain cases, errors are expected to be consistently sent for every occurrence of a specific issue. While telemetry
    /// is sampled on write, its processing can still overwhelm the SDK core with unnecessary overhead. Therefore,
    /// this API facilitates receiving only one error occurrence per process (further sampled with telemetry sample rate).
    ///
    /// - Parameters:
    ///   - id: The ID of the error - used to determine if it was already reported in this process.
    ///   - error: Closure to lazily evaluate error information (only when it will be sent).
    public func errorOnce(id: String, error: () -> (message: String, kind: String?, stack: String?)) {
        guard onceErrorIDs.contains(id) else {
            return
        }
        onceErrorIDs.insert(id)
        let errorInfo = error()
        self.error(id: id, message: errorInfo.message, kind: errorInfo.kind, stack: errorInfo.stack)
    }

    /// Report a Configuration Telemetry.
    ///
    /// The configuration can be partial, the telemtry should support accumulation of
    /// configuration for lazy initialization of the SDK.
    public func configuration(
        actionNameAttribute: String? = nil,
        allowFallbackToLocalStorage: Bool? = nil,
        allowUntrustedEvents: Bool? = nil,
        backgroundTasksEnabled: Bool? = nil,
        batchProcessingLevel: Int64? = nil,
        batchSize: Int64? = nil,
        batchUploadFrequency: Int64? = nil,
        dartVersion: String? = nil,
        defaultPrivacyLevel: String? = nil,
        forwardErrorsToLogs: Bool? = nil,
        initializationType: String? = nil,
        mobileVitalsUpdatePeriod: Int64? = nil,
        premiumSampleRate: Int64? = nil,
        reactNativeVersion: String? = nil,
        reactVersion: String? = nil,
        replaySampleRate: Int64? = nil,
        sessionReplaySampleRate: Int64? = nil,
        sessionSampleRate: Int64? = nil,
        silentMultipleInit: Bool? = nil,
        startSessionReplayRecordingManually: Bool? = nil,
        telemetryConfigurationSampleRate: Int64? = nil,
        telemetrySampleRate: Int64? = nil,
        traceSampleRate: Int64? = nil,
        trackBackgroundEvents: Bool? = nil,
        trackCrossPlatformLongTasks: Bool? = nil,
        trackErrors: Bool? = nil,
        trackFlutterPerformance: Bool? = nil,
        trackFrustrations: Bool? = nil,
        trackInteractions: Bool? = nil,
        trackLongTask: Bool? = nil,
        trackNativeErrors: Bool? = nil,
        trackNativeLongTasks: Bool? = nil,
        trackNativeViews: Bool? = nil,
        trackNetworkRequests: Bool? = nil,
        trackResources: Bool? = nil,
        trackSessionAcrossSubdomains: Bool? = nil,
        trackUserInteractions: Bool? = nil,
        trackViewsManually: Bool? = nil,
        useAllowedTracingOrigins: Bool? = nil,
        useAllowedTracingUrls: Bool? = nil,
        useBeforeSend: Bool? = nil,
        useCrossSiteSessionCookie: Bool? = nil,
        useExcludedActivityUrls: Bool? = nil,
        useFirstPartyHosts: Bool? = nil,
        useLocalEncryption: Bool? = nil,
        useProxy: Bool? = nil,
        useSecureSessionCookie: Bool? = nil,
        useTracing: Bool? = nil,
        useWorkerUrl: Bool? = nil
    ) {
        self.report(configuration: .init(
            actionNameAttribute: actionNameAttribute,
            allowFallbackToLocalStorage: allowFallbackToLocalStorage,
            allowUntrustedEvents: allowUntrustedEvents,
            backgroundTasksEnabled: backgroundTasksEnabled,
            batchProcessingLevel: batchProcessingLevel,
            batchSize: batchSize,
            batchUploadFrequency: batchUploadFrequency,
            dartVersion: dartVersion,
            defaultPrivacyLevel: defaultPrivacyLevel,
            forwardErrorsToLogs: forwardErrorsToLogs,
            initializationType: initializationType,
            mobileVitalsUpdatePeriod: mobileVitalsUpdatePeriod,
            premiumSampleRate: premiumSampleRate,
            reactNativeVersion: reactNativeVersion,
            reactVersion: reactVersion,
            replaySampleRate: replaySampleRate,
            sessionReplaySampleRate: sessionReplaySampleRate,
            sessionSampleRate: sessionSampleRate,
            silentMultipleInit: silentMultipleInit,
            startSessionReplayRecordingManually: startSessionReplayRecordingManually,
            telemetryConfigurationSampleRate: telemetryConfigurationSampleRate,
            telemetrySampleRate: telemetrySampleRate,
            traceSampleRate: traceSampleRate,
            trackBackgroundEvents: trackBackgroundEvents,
            trackCrossPlatformLongTasks: trackCrossPlatformLongTasks,
            trackErrors: trackErrors,
            trackFlutterPerformance: trackFlutterPerformance,
            trackFrustrations: trackFrustrations,
            trackInteractions: trackInteractions,
            trackLongTask: trackLongTask,
            trackNativeErrors: trackNativeErrors,
            trackNativeLongTasks: trackNativeLongTasks,
            trackNativeViews: trackNativeViews,
            trackNetworkRequests: trackNetworkRequests,
            trackResources: trackResources,
            trackSessionAcrossSubdomains: trackSessionAcrossSubdomains,
            trackUserInteractions: trackUserInteractions,
            trackViewsManually: trackViewsManually,
            useAllowedTracingOrigins: useAllowedTracingOrigins,
            useAllowedTracingUrls: useAllowedTracingUrls,
            useBeforeSend: useBeforeSend,
            useCrossSiteSessionCookie: useCrossSiteSessionCookie,
            useExcludedActivityUrls: useExcludedActivityUrls,
            useFirstPartyHosts: useFirstPartyHosts,
            useLocalEncryption: useLocalEncryption,
            useProxy: useProxy,
            useSecureSessionCookie: useSecureSessionCookie,
            useTracing: useTracing,
            useWorkerUrl: useWorkerUrl
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
            actionNameAttribute: other.actionNameAttribute ?? actionNameAttribute,
            allowFallbackToLocalStorage: other.allowFallbackToLocalStorage ?? allowFallbackToLocalStorage,
            allowUntrustedEvents: other.allowUntrustedEvents ?? allowUntrustedEvents,
            backgroundTasksEnabled: other.backgroundTasksEnabled ?? backgroundTasksEnabled,
            batchProcessingLevel: other.batchProcessingLevel ?? batchProcessingLevel,
            batchSize: other.batchSize ?? batchSize,
            batchUploadFrequency: other.batchUploadFrequency ?? batchUploadFrequency,
            dartVersion: other.dartVersion ?? dartVersion,
            defaultPrivacyLevel: other.defaultPrivacyLevel ?? defaultPrivacyLevel,
            forwardErrorsToLogs: other.forwardErrorsToLogs ?? forwardErrorsToLogs,
            initializationType: other.initializationType ?? initializationType,
            mobileVitalsUpdatePeriod: other.mobileVitalsUpdatePeriod ?? mobileVitalsUpdatePeriod,
            premiumSampleRate: other.premiumSampleRate ?? premiumSampleRate,
            reactNativeVersion: other.reactNativeVersion ?? reactNativeVersion,
            reactVersion: other.reactVersion ?? reactVersion,
            replaySampleRate: other.replaySampleRate ?? replaySampleRate,
            sessionReplaySampleRate: other.sessionReplaySampleRate ?? sessionReplaySampleRate,
            sessionSampleRate: other.sessionSampleRate ?? sessionSampleRate,
            silentMultipleInit: other.silentMultipleInit ?? silentMultipleInit,
            startSessionReplayRecordingManually: other.startSessionReplayRecordingManually ?? startSessionReplayRecordingManually,
            telemetryConfigurationSampleRate: other.telemetryConfigurationSampleRate ?? telemetryConfigurationSampleRate,
            telemetrySampleRate: other.telemetrySampleRate ?? telemetrySampleRate,
            traceSampleRate: other.traceSampleRate ?? traceSampleRate,
            trackBackgroundEvents: other.trackBackgroundEvents ?? trackBackgroundEvents,
            trackCrossPlatformLongTasks: other.trackCrossPlatformLongTasks ?? trackCrossPlatformLongTasks,
            trackErrors: other.trackErrors ?? trackErrors,
            trackFlutterPerformance: other.trackFlutterPerformance ?? trackFlutterPerformance,
            trackFrustrations: other.trackFrustrations ?? trackFrustrations,
            trackInteractions: other.trackInteractions ?? trackInteractions,
            trackLongTask: other.trackLongTask ?? trackLongTask,
            trackNativeErrors: other.trackNativeErrors ?? trackNativeErrors,
            trackNativeLongTasks: other.trackNativeLongTasks ?? trackNativeLongTasks,
            trackNativeViews: other.trackNativeViews ?? trackNativeViews,
            trackNetworkRequests: other.trackNetworkRequests ?? trackNetworkRequests,
            trackResources: other.trackResources ?? trackResources,
            trackSessionAcrossSubdomains: other.trackSessionAcrossSubdomains ?? trackSessionAcrossSubdomains,
            trackUserInteractions: other.trackUserInteractions ?? trackUserInteractions,
            trackViewsManually: other.trackViewsManually ?? trackViewsManually,
            useAllowedTracingOrigins: other.useAllowedTracingOrigins ?? useAllowedTracingOrigins,
            useAllowedTracingUrls: other.useAllowedTracingUrls ?? useAllowedTracingUrls,
            useBeforeSend: other.useBeforeSend ?? useBeforeSend,
            useCrossSiteSessionCookie: other.useCrossSiteSessionCookie ?? useCrossSiteSessionCookie,
            useExcludedActivityUrls: other.useExcludedActivityUrls ?? useExcludedActivityUrls,
            useFirstPartyHosts: other.useFirstPartyHosts ?? useFirstPartyHosts,
            useLocalEncryption: other.useLocalEncryption ?? useLocalEncryption,
            useProxy: other.useProxy ?? useProxy,
            useSecureSessionCookie: other.useSecureSessionCookie ?? useSecureSessionCookie,
            useTracing: other.useTracing ?? useTracing,
            useWorkerUrl: other.useWorkerUrl ?? useWorkerUrl
        )
    }
}
