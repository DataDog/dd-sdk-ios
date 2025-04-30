/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogLogs

@objc
public enum DDLogLevel: Int {
    case debug
    case info
    case notice
    case warn
    case error
    case critical

    internal init(_ swift: LogLevel) {
        switch swift {
        case .debug:    self = .debug
        case .info:     self = .info
        case .notice:   self = .notice
        case .warn:     self = .warn
        case .error:    self = .error
        case .critical: self = .critical
        }
    }

    internal var swift: LogLevel {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }
}

@objc
public class DDLogsConfiguration: NSObject {
    internal var configuration: Logs.Configuration

    /// Overrides the custom server endpoint where Logs are sent.
    @objc public var customEndpoint: URL? {
        get { configuration.customEndpoint }
        set { configuration.customEndpoint = newValue }
    }

    /// Creates a Logs configuration object.
    ///
    /// - Parameters:
    ///   - customEndpoint: Overrides the custom server endpoint where Logs are sent.
    @objc
    public init(
        customEndpoint: URL? = nil
    ) {
        configuration = .init(
            customEndpoint: customEndpoint
        )
    }

    /// Sets the custom mapper for `DDLogEvent`. This can be used to modify logs before they are send to Datadog.
    ///
    /// The implementation should obtain a mutable version of the `DDLogEvent`, modify it and return it. Returning `nil` will result
    /// with dropping the Log event entirely, so it won't be send to Datadog.
    @objc
    public func setEventMapper(_ mapper: @escaping (DDLogEvent) -> DDLogEvent?) {
        configuration.eventMapper = { swiftEvent in
            let objcEvent = DDLogEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }
}

@objc
public class DDLogs: NSObject {
    @objc
    public static func enable(
        with configuration: DDLogsConfiguration = .init()
    ) {
        Logs.enable(with: configuration.configuration)
    }

    @objc
    public static func addAttribute(forKey key: String, value: Any) {
        Logs.addAttribute(forKey: key, value: AnyEncodable(value))
    }

    @objc
    public static func removeAttribute(forKey key: String) {
        Logs.removeAttribute(forKey: key)
    }
}

@objc
public class DDLoggerConfiguration: NSObject {
    internal var configuration: Logger.Configuration

    /// The service name  (default value is set to application bundle identifier)
    @objc public var service: String? {
        get { configuration.service }
        set { configuration.service = newValue }
    }

    /// The logger custom name (default value is set to main bundle identifier)
    @objc public var name: String? {
        get { configuration.name }
        set { configuration.name = newValue }
    }

    /// Enriches logs with network connection info.
    ///
    /// This means: reachability status, connection type, mobile carrier name and many more will be added to each log.
    /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
    ///
    /// `false` by default
    @objc public var networkInfoEnabled: Bool {
        get { configuration.networkInfoEnabled }
        set { configuration.networkInfoEnabled = newValue }
    }

    /// Enables the logs integration with RUM.
    /// 
    /// If enabled all the logs will be enriched with the current RUM View information and
    /// it will be possible to see all the logs sent during a specific View lifespan in the RUM Explorer.
    ///
    /// `true` by default
    @objc public var bundleWithRumEnabled: Bool {
        get { configuration.bundleWithRumEnabled }
        set { configuration.bundleWithRumEnabled = newValue }
    }

    /// Enables the logs integration with active span API from Tracing.
    ///
    /// If enabled all the logs will be bundled with the `DatadogTracer.shared().activeSpan` trace and
    /// it will be possible to see all the logs sent during that specific trace.
    ///
    /// `true` by default
    @objc public var bundleWithTraceEnabled: Bool {
        get { configuration.bundleWithTraceEnabled }
        set { configuration.bundleWithTraceEnabled = newValue }
    }

    /// Sets the sampling rate for logging.
    ///
    /// The sampling rate must be a value between `0` and `100`. A value of `0` means no logs will be processed, `100`
    /// means all logs will be processed.
    ///
    /// By default sampling is disabled, meaning that all logs are being processed).
    @objc public var remoteSampleRate: Float {
        get { configuration.remoteSampleRate }
        set { configuration.remoteSampleRate = newValue }
    }

    /// Enables  logs to be printed to debugger console.
    ///
    /// `false` by default.
    @objc public var printLogsToConsole: Bool {
        get { configuration.consoleLogFormat != nil }
        set { configuration.consoleLogFormat = newValue ? .short : nil }
    }

    /// Set the minim log level reported to Datadog servers.
    /// Any log with a level equal or above the threshold will be sent.
    ///
    /// Note: this setting doesn't impact logs printed to the console if `printLogsToConsole(_:)`
    /// is used - all logs will be printed, no matter of their level.
    ///
    /// `DDLogLevel.debug` by default
    @objc public var remoteLogThreshold: DDLogLevel {
        get { DDLogLevel(configuration.remoteLogThreshold) }
        set { configuration.remoteLogThreshold = newValue.swift }
    }

    /// Creates a Logger Configuration.
    ///
    /// - Parameters:
    ///   - service: The service name  (default value is set to application bundle identifier)
    ///   - name: The logger custom name (default value is set to main bundle identifier)
    ///   - networkInfoEnabled: Enriches logs with network connection info. `false` by default.
    ///   - bundleWithRumEnabled: Enables the logs integration with RUM. `true` by default.
    ///   - bundleWithTraceEnabled: Enables the logs integration with active span API from Tracing. `true` by default
    ///   - remoteSampleRate: The sample rate for remote logging. **When set to `0`, no log entries will be sent to Datadog servers.**
    ///   - remoteLogThreshold: Set the minimum log level reported to Datadog servers. .debug by default.
    ///   - printLogsToConsole: Format to use when printing logs to console - either `.short` or `.json`.
    @objc
    public init(
        service: String? = nil,
        name: String? = nil,
        networkInfoEnabled: Bool = false,
        bundleWithRumEnabled: Bool = true,
        bundleWithTraceEnabled: Bool = true,
        remoteSampleRate: SampleRate = .maxSampleRate,
        remoteLogThreshold: DDLogLevel = .debug,
        printLogsToConsole: Bool = false
    ) {
        configuration = .init(
            service: service,
            name: name,
            networkInfoEnabled: networkInfoEnabled,
            bundleWithRumEnabled: bundleWithRumEnabled,
            bundleWithTraceEnabled: bundleWithTraceEnabled,
            remoteSampleRate: remoteSampleRate,
            remoteLogThreshold: remoteLogThreshold.swift,
            consoleLogFormat: printLogsToConsole ? .short : nil
        )
    }
}

@objc
public class DDLogger: NSObject {
    internal let sdkLogger: LoggerProtocol

    internal init(sdkLogger: LoggerProtocol) {
        self.sdkLogger = sdkLogger
    }

    // MARK: - Public

    @objc
    public func debug(_ message: String) {
        sdkLogger.debug(message)
    }

    @objc
    public func debug(_ message: String, attributes: [String: Any]) {
        sdkLogger.debug(message, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func debug(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.debug(message, error: error, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func info(_ message: String) {
        sdkLogger.info(message)
    }

    @objc
    public func info(_ message: String, attributes: [String: Any]) {
        sdkLogger.info(message, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func info(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.info(message, error: error, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func notice(_ message: String) {
        sdkLogger.notice(message)
    }

    @objc
    public func notice(_ message: String, attributes: [String: Any]) {
        sdkLogger.notice(message, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func notice(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.notice(message, error: error, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func warn(_ message: String) {
        sdkLogger.warn(message)
    }

    @objc
    public func warn(_ message: String, attributes: [String: Any]) {
        sdkLogger.warn(message, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func warn(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.warn(message, error: error, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func error(_ message: String) {
        sdkLogger.error(message)
    }

    @objc
    public func error(_ message: String, attributes: [String: Any]) {
        sdkLogger.error(message, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func error(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.error(message, error: error, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func critical(_ message: String) {
        sdkLogger.critical(message)
    }

    @objc
    public func critical(_ message: String, attributes: [String: Any]) {
        sdkLogger.critical(message, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func critical(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.critical(message, error: error, attributes: attributes.dd.swiftAttributes)
    }

    @objc
    public func addAttribute(forKey key: String, value: Any) {
        sdkLogger.addAttribute(forKey: key, value: AnyEncodable(value))
    }

    @objc
    public func removeAttribute(forKey key: String) {
        sdkLogger.removeAttribute(forKey: key)
    }

    @objc
    public func addTag(withKey key: String, value: String) {
        sdkLogger.addTag(withKey: key, value: value)
    }

    @objc
    public func removeTag(withKey key: String) {
        sdkLogger.removeTag(withKey: key)
    }

    @objc
    public func add(tag: String) {
        sdkLogger.add(tag: tag)
    }

    @objc
    public func remove(tag: String) {
        sdkLogger.remove(tag: tag)
    }

    @objc
    public static func create(with configuration: DDLoggerConfiguration = .init()) -> DDLogger {
        return DDLogger(sdkLogger: Logger.create(with: configuration.configuration))
    }
}
