/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import struct Datadog.DDAnyEncodable
import class Datadog.Logger

@objc
public enum DDSDKVerbosityLevel: Int {
    case none
    case debug
    case info
    case notice
    case warn
    case error
    case critical
}

@objc
public enum DDLogLevel: Int {
    case debug
    case info
    case notice
    case warn
    case error
    case critical
}

@objc
public class DDLogger: NSObject {
    internal let sdkLogger: Logger

    internal init(sdkLogger: Logger) {
        self.sdkLogger = sdkLogger
    }

    // MARK: - Public

    @objc
    public func debug(_ message: String) {
        sdkLogger.debug(message)
    }

    @objc
    public func debug(_ message: String, attributes: [String: Any]) {
        sdkLogger.debug(message, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func debug(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.debug(message, error: error, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func info(_ message: String) {
        sdkLogger.info(message)
    }

    @objc
    public func info(_ message: String, attributes: [String: Any]) {
        sdkLogger.info(message, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func info(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.info(message, error: error, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func notice(_ message: String) {
        sdkLogger.notice(message)
    }

    @objc
    public func notice(_ message: String, attributes: [String: Any]) {
        sdkLogger.notice(message, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func notice(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.notice(message, error: error, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func warn(_ message: String) {
        sdkLogger.warn(message)
    }

    @objc
    public func warn(_ message: String, attributes: [String: Any]) {
        sdkLogger.warn(message, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func warn(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.warn(message, error: error, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func error(_ message: String) {
        sdkLogger.error(message)
    }

    @objc
    public func error(_ message: String, attributes: [String: Any]) {
        sdkLogger.error(message, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func error(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.error(message, error: error, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func critical(_ message: String) {
        sdkLogger.critical(message)
    }

    @objc
    public func critical(_ message: String, attributes: [String: Any]) {
        sdkLogger.critical(message, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func critical(_ message: String, error: NSError, attributes: [String: Any]) {
        sdkLogger.critical(message, error: error, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addAttribute(forKey key: String, value: Any) {
        sdkLogger.addAttribute(forKey: key, value: DDAnyEncodable(value))
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
    public static func builder() -> DDLoggerBuilder {
        return DDLoggerBuilder(sdkBuilder: Logger.builder)
    }
}

@objc
public class DDLoggerBuilder: NSObject {
    internal let sdkBuilder: Logger.Builder

    internal init(sdkBuilder: Logger.Builder) {
        self.sdkBuilder = sdkBuilder
    }

    // MARK: - Public

    @objc
    public func set(serviceName: String) {
        _ = sdkBuilder.set(serviceName: serviceName)
    }

    @objc
    public func set(loggerName: String) {
        _ = sdkBuilder.set(loggerName: loggerName)
    }

    @objc
    public func sendNetworkInfo(_ enabled: Bool) {
        _ = sdkBuilder.sendNetworkInfo(enabled)
    }

    @objc
    public func sendLogsToDatadog(_ enabled: Bool) {
        _ = sdkBuilder.sendLogsToDatadog(enabled)
    }

    @objc
    public func printLogsToConsole(_ enabled: Bool) {
        _ = sdkBuilder.printLogsToConsole(enabled)
    }

    @objc
    public func set(datadogReportingThreshold: DDLogLevel) {
        switch datadogReportingThreshold {
        case .debug: _ = sdkBuilder.set(datadogReportingThreshold: .debug)
        case .info: _ = sdkBuilder.set(datadogReportingThreshold: .info)
        case .notice: _ = sdkBuilder.set(datadogReportingThreshold: .notice)
        case .warn: _ = sdkBuilder.set(datadogReportingThreshold: .warn)
        case .error: _ = sdkBuilder.set(datadogReportingThreshold: .error)
        case .critical: _ = sdkBuilder.set(datadogReportingThreshold: .critical)
        }
    }

    @objc
    public func build() -> DDLogger {
        return DDLogger(sdkLogger: sdkBuilder.build())
    }
}
