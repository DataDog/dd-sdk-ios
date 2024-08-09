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
    public let appHangThreshold: Int64?
    public let backgroundTasksEnabled: Bool?
    public let batchProcessingLevel: Int64?
    public let batchSize: Int64?
    public let batchUploadFrequency: Int64?
    public let dartVersion: String?
    public let defaultPrivacyLevel: String?
    public let forwardErrorsToLogs: Bool?
    public let initializationType: String?
    public let mobileVitalsUpdatePeriod: Int64?
    public let reactNativeVersion: String?
    public let reactVersion: String?
    public let sessionReplaySampleRate: Int64?
    public let sessionSampleRate: Int64?
    public let silentMultipleInit: Bool?
    public let startRecordingImmediately: Bool?
    public let startSessionReplayRecordingManually: Bool?
    public let telemetryConfigurationSampleRate: Int64?
    public let telemetrySampleRate: Int64?
    public let tracerAPI: String?
    public let tracerAPIVersion: String?
    public let traceSampleRate: Int64?
    public let trackBackgroundEvents: Bool?
    public let trackCrossPlatformLongTasks: Bool?
    public let trackErrors: Bool?
    public let trackFlutterPerformance: Bool?
    public let trackFrustrations: Bool?
    public let trackLongTask: Bool?
    public let trackNativeErrors: Bool?
    public let trackNativeLongTasks: Bool?
    public let trackNativeViews: Bool?
    public let trackNetworkRequests: Bool?
    public let trackResources: Bool?
    public let trackSessionAcrossSubdomains: Bool?
    public let trackUserInteractions: Bool?
    public let trackViewsManually: Bool?
    public let unityVersion: String?
    public let useAllowedTracingUrls: Bool?
    public let useBeforeSend: Bool?
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
    case error(id: String, message: String, kind: String, stack: String)
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

public extension Telemetry {
    /// Starts a method call.
    ///
    /// - Parameters:
    ///   - operationName: Platform agnostic name of the operation.
    ///   - callerClass: The name of the class that calls the method.
    ///   - samplingRate: The sampling rate of the method call. Value between `0.0` and `100.0`, where `0.0` means NO event will be processed and `100.0` means ALL events will be processed. Note that this value is multiplicated by telemetry sampling (by default 20%) and metric events sampling (hardcoded to 15%). Making it effectively 3% sampling rate for sending events, when this value is set to `100`.
    ///
    /// - Returns: A `MethodCalledTrace` instance to be used to stop the method call and measure it's execution time. It can be `nil` if the method call is not sampled.
    func startMethodCalled(
        operationName: String,
        callerClass: String,
        samplingRate: Float = 100.0
    ) -> MethodCalledTrace? {
        if Sampler(samplingRate: samplingRate).sample() {
            return MethodCalledTrace(
                operationName: operationName,
                callerClass: callerClass
            )
        } else {
            return nil
        }
    }

    /// Stops a method call, transforms method call metric to telemetry message,
    /// and transmits on the message-bus of the core.
    ///
    /// - Parameters
    ///   - metric: The `MethodCalledTrace` instance.
    ///   - isSuccessful: A flag indicating if the method call was successful.
    func stopMethodCalled(_ metric: MethodCalledTrace?, isSuccessful: Bool = true) {
        if let metric = metric {
            send(telemetry: metric.asTelemetryMetric(isSuccessful: isSuccessful))
        }
    }
}

/// A metric to measure the time of a method call.
public struct MethodCalledTrace {
    let operationName: String
    let callerClass: String
    let startTime = Date()

    var exectutionTime: Int64 {
        return -startTime.timeIntervalSinceNow.toInt64Nanoseconds
    }

    func asTelemetryMetric(isSuccessful: Bool) -> TelemetryMessage {
        return .metric(
            name: MethodCalledMetric.name,
            attributes: [
                MethodCalledMetric.executionTime: exectutionTime,
                MethodCalledMetric.operationName: operationName,
                MethodCalledMetric.callerClass: callerClass,
                MethodCalledMetric.isSuccessful: isSuccessful,
                SDKMetricFields.typeKey: MethodCalledMetric.typeValue
            ]
        )
    }
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
    public func error(id: String, message: String, kind: String, stack: String) {
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
    public func debug(_ message: String, attributes: [String: Encodable]? = nil, file: String = #fileID, line: Int = #line) {
        debug(id: "\(file):\(line):\(message)", message: message, attributes: attributes)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - kind: The kind of error.
    ///   - stack: The stack trace.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, kind: String? = nil, stack: String? = nil, file: String = #fileID, line: Int = #line) {
        error(
            id: "\(file):\(line):\(message)",
            message: message,
            kind: kind ?? "\(file)",
            stack: stack ?? "\(file):\(line)"
        )
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ error: DDError, file: String = #fileID, line: Int = #line) {
        self.error(error.message, kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, error: DDError, file: String = #fileID, line: Int = #line) {
        self.error("\(message) - \(error.message)", kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ error: Error, file: String = #fileID, line: Int = #line) {
        self.error(DDError(error: error), file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    public func error(_ message: String, error: Error, file: String = #fileID, line: Int = #line) {
        self.error(message, error: DDError(error: error), file: file, line: line)
    }

    /// Report a Configuration Telemetry.
    ///
    /// The configuration can be partial, the telemetry supports accumulation of
    /// configuration for lazy initialization of different SDK features.
    public func configuration(
        actionNameAttribute: String? = nil,
        allowFallbackToLocalStorage: Bool? = nil,
        allowUntrustedEvents: Bool? = nil,
        appHangThreshold: Int64? = nil,
        backgroundTasksEnabled: Bool? = nil,
        batchProcessingLevel: Int64? = nil,
        batchSize: Int64? = nil,
        batchUploadFrequency: Int64? = nil,
        dartVersion: String? = nil,
        defaultPrivacyLevel: String? = nil,
        forwardErrorsToLogs: Bool? = nil,
        initializationType: String? = nil,
        mobileVitalsUpdatePeriod: Int64? = nil,
        reactNativeVersion: String? = nil,
        reactVersion: String? = nil,
        sessionReplaySampleRate: Int64? = nil,
        sessionSampleRate: Int64? = nil,
        silentMultipleInit: Bool? = nil,
        startRecordingImmediately: Bool? = nil,
        startSessionReplayRecordingManually: Bool? = nil,
        telemetryConfigurationSampleRate: Int64? = nil,
        telemetrySampleRate: Int64? = nil,
        tracerAPI: String? = nil,
        tracerAPIVersion: String? = nil,
        traceSampleRate: Int64? = nil,
        trackBackgroundEvents: Bool? = nil,
        trackCrossPlatformLongTasks: Bool? = nil,
        trackErrors: Bool? = nil,
        trackFlutterPerformance: Bool? = nil,
        trackFrustrations: Bool? = nil,
        trackLongTask: Bool? = nil,
        trackNativeErrors: Bool? = nil,
        trackNativeLongTasks: Bool? = nil,
        trackNativeViews: Bool? = nil,
        trackNetworkRequests: Bool? = nil,
        trackResources: Bool? = nil,
        trackSessionAcrossSubdomains: Bool? = nil,
        trackUserInteractions: Bool? = nil,
        trackViewsManually: Bool? = nil,
        unityVersion: String? = nil,
        useAllowedTracingUrls: Bool? = nil,
        useBeforeSend: Bool? = nil,
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
            appHangThreshold: appHangThreshold,
            backgroundTasksEnabled: backgroundTasksEnabled,
            batchProcessingLevel: batchProcessingLevel,
            batchSize: batchSize,
            batchUploadFrequency: batchUploadFrequency,
            dartVersion: dartVersion,
            defaultPrivacyLevel: defaultPrivacyLevel,
            forwardErrorsToLogs: forwardErrorsToLogs,
            initializationType: initializationType,
            mobileVitalsUpdatePeriod: mobileVitalsUpdatePeriod,
            reactNativeVersion: reactNativeVersion,
            reactVersion: reactVersion,
            sessionReplaySampleRate: sessionReplaySampleRate,
            sessionSampleRate: sessionSampleRate,
            silentMultipleInit: silentMultipleInit,
            startRecordingImmediately: startRecordingImmediately,
            startSessionReplayRecordingManually: startSessionReplayRecordingManually,
            telemetryConfigurationSampleRate: telemetryConfigurationSampleRate,
            telemetrySampleRate: telemetrySampleRate,
            tracerAPI: tracerAPI,
            tracerAPIVersion: tracerAPIVersion,
            traceSampleRate: traceSampleRate,
            trackBackgroundEvents: trackBackgroundEvents,
            trackCrossPlatformLongTasks: trackCrossPlatformLongTasks,
            trackErrors: trackErrors,
            trackFlutterPerformance: trackFlutterPerformance,
            trackFrustrations: trackFrustrations,
            trackLongTask: trackLongTask,
            trackNativeErrors: trackNativeErrors,
            trackNativeLongTasks: trackNativeLongTasks,
            trackNativeViews: trackNativeViews,
            trackNetworkRequests: trackNetworkRequests,
            trackResources: trackResources,
            trackSessionAcrossSubdomains: trackSessionAcrossSubdomains,
            trackUserInteractions: trackUserInteractions,
            trackViewsManually: trackViewsManually,
            unityVersion: unityVersion,
            useAllowedTracingUrls: useAllowedTracingUrls,
            useBeforeSend: useBeforeSend,
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
    public func startMethodCalled(operationName: String, callerClass: String, samplingRate: Float) -> MethodCalledTrace? { return nil }
    public func stopMethodCalled(_ metric: MethodCalledTrace?, isSuccessful: Bool) { }
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

extension DatadogCoreProtocol {
    /// Provides access to the `Storage` associated with the core.
    /// - Returns: The `Storage` instance.
    public var storage: Storage { CoreStorage(core: self) }
}

extension ConfigurationTelemetry {
    public func merged(with other: Self) -> Self {
        .init(
            actionNameAttribute: other.actionNameAttribute ?? actionNameAttribute,
            allowFallbackToLocalStorage: other.allowFallbackToLocalStorage ?? allowFallbackToLocalStorage,
            allowUntrustedEvents: other.allowUntrustedEvents ?? allowUntrustedEvents,
            appHangThreshold: other.appHangThreshold ?? appHangThreshold,
            backgroundTasksEnabled: other.backgroundTasksEnabled ?? backgroundTasksEnabled,
            batchProcessingLevel: other.batchProcessingLevel ?? batchProcessingLevel,
            batchSize: other.batchSize ?? batchSize,
            batchUploadFrequency: other.batchUploadFrequency ?? batchUploadFrequency,
            dartVersion: other.dartVersion ?? dartVersion,
            defaultPrivacyLevel: other.defaultPrivacyLevel ?? defaultPrivacyLevel,
            forwardErrorsToLogs: other.forwardErrorsToLogs ?? forwardErrorsToLogs,
            initializationType: other.initializationType ?? initializationType,
            mobileVitalsUpdatePeriod: other.mobileVitalsUpdatePeriod ?? mobileVitalsUpdatePeriod,
            reactNativeVersion: other.reactNativeVersion ?? reactNativeVersion,
            reactVersion: other.reactVersion ?? reactVersion,
            sessionReplaySampleRate: other.sessionReplaySampleRate ?? sessionReplaySampleRate,
            sessionSampleRate: other.sessionSampleRate ?? sessionSampleRate,
            silentMultipleInit: other.silentMultipleInit ?? silentMultipleInit,
            startRecordingImmediately: other.startRecordingImmediately ?? startRecordingImmediately,
            startSessionReplayRecordingManually: other.startSessionReplayRecordingManually ?? startSessionReplayRecordingManually,
            telemetryConfigurationSampleRate: other.telemetryConfigurationSampleRate ?? telemetryConfigurationSampleRate,
            telemetrySampleRate: other.telemetrySampleRate ?? telemetrySampleRate,
            tracerAPI: other.tracerAPI ?? tracerAPI,
            tracerAPIVersion: other.tracerAPIVersion ?? tracerAPIVersion,
            traceSampleRate: other.traceSampleRate ?? traceSampleRate,
            trackBackgroundEvents: other.trackBackgroundEvents ?? trackBackgroundEvents,
            trackCrossPlatformLongTasks: other.trackCrossPlatformLongTasks ?? trackCrossPlatformLongTasks,
            trackErrors: other.trackErrors ?? trackErrors,
            trackFlutterPerformance: other.trackFlutterPerformance ?? trackFlutterPerformance,
            trackFrustrations: other.trackFrustrations ?? trackFrustrations,
            trackLongTask: other.trackLongTask ?? trackLongTask,
            trackNativeErrors: other.trackNativeErrors ?? trackNativeErrors,
            trackNativeLongTasks: other.trackNativeLongTasks ?? trackNativeLongTasks,
            trackNativeViews: other.trackNativeViews ?? trackNativeViews,
            trackNetworkRequests: other.trackNetworkRequests ?? trackNetworkRequests,
            trackResources: other.trackResources ?? trackResources,
            trackSessionAcrossSubdomains: other.trackSessionAcrossSubdomains ?? trackSessionAcrossSubdomains,
            trackUserInteractions: other.trackUserInteractions ?? trackUserInteractions,
            trackViewsManually: other.trackViewsManually ?? trackViewsManually,
            unityVersion: other.unityVersion ?? unityVersion,
            useAllowedTracingUrls: other.useAllowedTracingUrls ?? useAllowedTracingUrls,
            useBeforeSend: other.useBeforeSend ?? useBeforeSend,
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
