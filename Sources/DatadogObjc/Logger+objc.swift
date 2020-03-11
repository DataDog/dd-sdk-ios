/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
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

@objcMembers
public class DDLogger: NSObject {
    internal let sdkLogger: Logger

    internal init(sdkLogger: Logger) {
        self.sdkLogger = sdkLogger
    }

    // MARK: - Public

    public func debug(_ message: String) {
        sdkLogger.debug(message)
    }

    public func debug(_ message: String, attributes: [String: Any]) {
        sdkLogger.debug(message, attributes: castAttributesToSwift(attributes))
    }

    public func info(_ message: String) {
        sdkLogger.info(message)
    }

    public func info(_ message: String, attributes: [String: Any]) {
        sdkLogger.info(message, attributes: castAttributesToSwift(attributes))
    }

    public func notice(_ message: String) {
        sdkLogger.notice(message)
    }

    public func notice(_ message: String, attributes: [String: Any]) {
        sdkLogger.notice(message, attributes: castAttributesToSwift(attributes))
    }

    public func warn(_ message: String) {
        sdkLogger.warn(message)
    }

    public func warn(_ message: String, attributes: [String: Any]) {
        sdkLogger.warn(message, attributes: castAttributesToSwift(attributes))
    }

    public func error(_ message: String) {
        sdkLogger.error(message)
    }

    public func error(_ message: String, attributes: [String: Any]) {
        sdkLogger.error(message, attributes: castAttributesToSwift(attributes))
    }

    public func critical(_ message: String) {
        sdkLogger.critical(message)
    }

    public func critical(_ message: String, attributes: [String: Any]) {
        sdkLogger.critical(message, attributes: castAttributesToSwift(attributes))
    }

    public func addAttribute(forKey key: String, value: Any) {
        sdkLogger.addAttribute(forKey: key, value: AnyEncodable(value))
    }

    public func removeAttribute(forKey key: String) {
        sdkLogger.removeAttribute(forKey: key)
    }

    public func addTag(withKey key: String, value: String) {
        sdkLogger.addTag(withKey: key, value: value)
    }

    public func removeTag(withKey key: String) {
        sdkLogger.removeTag(withKey: key)
    }

    public func add(tag: String) {
        sdkLogger.add(tag: tag)
    }

    public func remove(tag: String) {
        sdkLogger.remove(tag: tag)
    }

    public static func builder() -> DDLoggerBuilder {
        return DDLoggerBuilder(sdkBuilder: Logger.builder)
    }

    // MARK: - Private

    private func castAttributesToSwift(_ attributes: [String: Any]) -> [String: Encodable] {
        return attributes.mapValues { AnyEncodable($0) }
    }
}

@objcMembers
public class DDLoggerBuilder: NSObject {
    internal let sdkBuilder: Logger.Builder

    internal init(sdkBuilder: Logger.Builder) {
        self.sdkBuilder = sdkBuilder
    }

    // MARK: - Public

    public func set(serviceName: String) {
        _ = sdkBuilder.set(serviceName: serviceName)
    }

    public func set(loggerName: String) {
        _ = sdkBuilder.set(loggerName: loggerName)
    }

    public func sendNetworkInfo(_ enabled: Bool) {
        _ = sdkBuilder.sendNetworkInfo(enabled)
    }

    public func sendLogsToDatadog(_ enabled: Bool) {
        _ = sdkBuilder.sendLogsToDatadog(enabled)
    }

    public func printLogsToConsole(_ enabled: Bool) {
        _ = sdkBuilder.printLogsToConsole(enabled)
    }

    public func build() -> DDLogger {
        return DDLogger(sdkLogger: sdkBuilder.build())
    }
}
