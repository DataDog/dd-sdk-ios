/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines the type of configuration telemetry events supported by the SDK.
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

public struct MetricTelemetry {
    /// The default sample rate for metric events (15%), applied in addition to the telemetry sample rate (20% by default).
    public static let defaultSampleRate: Float = 15

    /// The name of the metric.
    public let name: String

    /// The attributes associated with this metric.
    public let attributes: [String: Encodable]

    /// The sample rate for this metric, applied in addition to the telemetry sample rate.
    ///
    /// Must be a value between `0` (reject all) and `100` (keep all).
    ///
    /// Note: This sample rate is compounded with the telemetry sample rate. For example, if the telemetry sample rate is 20% (default)
    /// and this metric's sample rate is 15%, the effective sample rate for this metric will be 3%.
    ///
    /// This sample rate is applied in the telemetry receiver, after the metric has been processed by the SDK core (tail-based sampling).
    public let sampleRate: Float
}

/// Describes the type of the usage telemetry events supported by the SDK.
public enum UsageTelemetry {
    /// setTrackingConsent API
    case setTrackingConsent(TrackingConsent)
    /// stopSession API
    case stopSession
    /// startView API
    case startView
    /// addAction API
    case addAction
    /// addError API
    case addError
    /// setGlobalContext, setGlobalContextProperty, addAttribute APIs
    case setGlobalContext
    /// setUser, setUserProperty, setUserInfo APIs
    case setUser
    /// addFeatureFlagEvaluation API
    case addFeatureFlagEvaluation
    /// addFeatureFlagEvaluation API
    case addViewLoadingTime(ViewLoadingTime)

    /// Describes the properties of `addViewLoadingTime` usage telemetry.
    public struct ViewLoadingTime {
        /// Whether the available view is not active
        public let noActiveView: Bool
        /// Whether the view is not available
        public let noView: Bool
        /// Whether the loading time was overwritten
        public let overwritten: Bool
    }
}

/// Defines different types of telemetry messages supported by the SDK.
public enum TelemetryMessage {
    /// A debug log message.
    case debug(id: String, message: String, attributes: [String: Encodable]?)
    /// An execution error.
    case error(id: String, message: String, kind: String, stack: String)
    /// A configuration telemetry.
    case configuration(ConfigurationTelemetry)
    case metric(MetricTelemetry)
    case usage(UsageTelemetry)
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
    /// Starts timing a method call using the "Method Called" metric.
    ///
    /// - Parameters:
    ///   - operationName: A platform-agnostic name for the operation.
    ///   - callerClass: The name of the class that invokes the method.
    ///   - headSampleRate: The sample rate for **head-based** sampling of the method call metric. Must be a value between `0` (reject all) and `100` (keep all).
    ///
    /// Note: The head sample rate is compounded with the tail sample rate, which is configured in `stopMethodCalled()`. Both are applied
    /// in addition to the telemetry sample rate. For example, if the telemetry sample rate is 20% (default), the head sample rate is 1%, and the tail sample
    /// rate is 15% (default), the effective sample rate will be 20% x 1% x 15% = 0.03%.
    ///
    /// Unlike the telemetry sample rate and tail-based sampling in `stopMethodCalled()`, this sample rate is applied at the start of the method call timing.
    /// This head-based sampling reduces the impact of processing high-frequency metrics in the SDK core, as most samples can be dropped
    /// before being passed to the message bus.
    ///
    /// - Returns: A `MethodCalledTrace` instance for stopping the method call and measuring its execution time, or `nil` if the method call is not sampled.
    func startMethodCalled(
        operationName: String,
        callerClass: String,
        headSampleRate: Float
    ) -> MethodCalledTrace? {
        if Sampler(samplingRate: headSampleRate).sample() {
            return MethodCalledTrace(
                operationName: operationName,
                callerClass: callerClass
            )
        } else {
            return nil
        }
    }

    /// Stops timing a method call and posts a value for the "Method Called" metric.
    ///
    /// This method applies tail-based sampling in addition to the head-based sampling applied in `startMethodCalled()`.
    /// The tail sample rate is compounded with the head sample rate and the telemetry sample rate to determine the effective sample rate.
    ///
    /// - Parameters:
    ///   - metric: The `MethodCalledTrace` instance.
    ///   - isSuccessful: A flag indicating whether the method call was successful.
    ///   - tailSampleRate: The sample rate for **tail-based** sampling of the metric, applied in telemetry receiver after the metric is processed by the SDK core.
    ///     Defaults to `MetricTelemetry.defaultSampleRate` (15%).
    func stopMethodCalled(
        _ metric: MethodCalledTrace?,
        isSuccessful: Bool = true,
        tailSampleRate: Float = MetricTelemetry.defaultSampleRate
    ) {
        if let metric = metric {
            let executionTime = -metric.startTime.timeIntervalSinceNow.toInt64Nanoseconds
            send(
                telemetry: .metric(
                    MetricTelemetry(
                        name: MethodCalledMetric.name,
                        attributes: [
                            MethodCalledMetric.executionTime: executionTime,
                            MethodCalledMetric.operationName: metric.operationName,
                            MethodCalledMetric.callerClass: metric.callerClass,
                            MethodCalledMetric.isSuccessful: isSuccessful,
                            SDKMetricFields.typeKey: MethodCalledMetric.typeValue
                        ],
                        sampleRate: tailSampleRate
                    )
                )
            )
        }
    }
}

/// A metric to measure the time of a method call.
public struct MethodCalledTrace {
    let operationName: String
    let callerClass: String
    let startTime = Date()
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

    /// Collects a metric value.
    ///
    /// Metrics are reported as debug telemetry. Unlike regular events, they are not subject to duplicate filtering and
    /// are sampled at a different rate. Metric attributes are used to create facets for later querying and graphing.
    ///
    /// - Parameters:
    ///   - name: The name of the metric.
    ///   - attributes: The attributes associated with this metric.
    ///   - sampleRate: The sample rate for this metric, applied in addition to the telemetry sample rate (15% by default).
    ///     Must be a value between `0` (reject all) and `100` (keep all).
    ///
    ///     Note: This sample rate is compounded with the telemetry sample rate. For example, if the telemetry sample rate is 20% (default)
    ///     and this metric's sample rate is 15%, the effective sample rate for this metric will be 3%.
    ///
    ///     This sample rate is applied in the telemetry receiver, after the metric has been processed by the SDK core (tail-based sampling).
    public func metric(name: String, attributes: [String: Encodable], sampleRate: Float = MetricTelemetry.defaultSampleRate) {
        send(telemetry: .metric(MetricTelemetry(name: name, attributes: attributes, sampleRate: sampleRate)))
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
