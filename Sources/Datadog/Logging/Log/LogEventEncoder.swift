/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Encodable` representation of log. It gets sanitized before encoding.
/// All mutable properties are subject of sanitization.
public struct LogEvent: Encodable {
    /// The Log event status definitions.
    public enum Status: String, Encodable, CaseIterable {
        case debug
        case info
        case notice
        case warn
        case error
        case critical
        case emergency
    }
    public struct Attributes {
        /// Log custom attributes, They are subject for sanitization.
        public var userAttributes: [String: Encodable]
        /// Log attributes added internally by the SDK. They are not a subject for sanitization.
        internal let internalAttributes: [String: Encodable]?
    }
    public struct UserInfo {
        /// User ID, if any.
        public let id: String?
        /// Name representing the user, if any.
        public let name: String?
        /// User email, if any.
        public let email: String?
        /// User custom attributes, if any.
        public var extraInfo: [String: Encodable]
    }
    public struct Error {
        // The Log error kind
        public let kind: String?
        // The Log error message
        public let message: String?
        // The Log error stack
        public let stack: String?
    }

    /// The log's timestamp
    public let date: Date
    /// The log status
    public let status: Status
    /// The log message
    public var message: String
    /// The associated log error
    public let error: Error?
    /// The service name configured for Logs.
    public let serviceName: String
    /// The current log environement.
    public let environment: String
    /// The configured logger name.
    public let loggerName: String
    /// The current logger version.
    public let loggerVersion: String
    /// The thread's name this log event has been sent from.
    public let threadName: String?
    /// The current application version.
    public let applicationVersion: String
    /// Custom user information configured globally for the SDK.
    public var userInfo: UserInfo
    /// The network connection information from the moment the log was sent.
    public let networkConnectionInfo: NetworkConnectionInfo?
    /// The mobile carrier information from the moment the log was sent.
    public let mobileCarrierInfo: CarrierInfo?
    /// The attributes associated with this log.
    public var attributes: LogEvent.Attributes
    /// Tags associated with this log.
    public var tags: [String]?

    public func encode(to encoder: Encoder) throws {
        let sanitizedLog = LogEventSanitizer().sanitize(log: self)
        try LogEventEncoder().encode(sanitizedLog, to: encoder)
    }
}

/// Encodes `Log` to given encoder.
internal struct LogEventEncoder {
    /// Coding keys for permanent `Log` attributes.
    enum StaticCodingKeys: String, CodingKey {
        case date
        case status
        case message
        case serviceName = "service"
        case tags = "ddtags"

        // MARK: - Error

        case errorKind = "error.kind"
        case errorMessage = "error.message"
        case errorStack = "error.stack"

        // MARK: - Application info

        case applicationVersion = "version"

        // MARK: - Logger info

        case loggerName = "logger.name"
        case loggerVersion = "logger.version"
        case threadName = "logger.thread_name"

        // MARK: - User info

        case userId = "usr.id"
        case userName = "usr.name"
        case userEmail = "usr.email"

        // MARK: - Network connection info

        case networkReachability = "network.client.reachability"
        case networkAvailableInterfaces = "network.client.available_interfaces"
        case networkConnectionSupportsIPv4 = "network.client.supports_ipv4"
        case networkConnectionSupportsIPv6 = "network.client.supports_ipv6"
        case networkConnectionIsExpensive = "network.client.is_expensive"
        case networkConnectionIsConstrained = "network.client.is_constrained"

        // MARK: - Mobile carrier info

        case mobileNetworkCarrierName = "network.client.sim_carrier.name"
        case mobileNetworkCarrierISOCountryCode = "network.client.sim_carrier.iso_country"
        case mobileNetworkCarrierRadioTechnology = "network.client.sim_carrier.technology"
        case mobileNetworkCarrierAllowsVoIP = "network.client.sim_carrier.allows_voip"
    }

    /// Coding keys for dynamic `Log` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }

    func encode(_ log: LogEvent, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticCodingKeys.self)
        try container.encode(log.date, forKey: .date)
        try container.encode(log.status, forKey: .status)
        try container.encode(log.message, forKey: .message)
        try container.encode(log.serviceName, forKey: .serviceName)

        // Encode log.error properties
        if let someError = log.error {
            try container.encode(someError.kind, forKey: .errorKind)
            try container.encode(someError.message, forKey: .errorMessage)
            try container.encode(someError.stack, forKey: .errorStack)
        }

        // Encode logger info
        try container.encode(log.loggerName, forKey: .loggerName)
        try container.encode(log.loggerVersion, forKey: .loggerVersion)
        try container.encode(log.threadName, forKey: .threadName)

        // Encode application info
        try container.encode(log.applicationVersion, forKey: .applicationVersion)

        // Encode user info
        try log.userInfo.id.ifNotNil { try container.encode($0, forKey: .userId) }
        try log.userInfo.name.ifNotNil { try container.encode($0, forKey: .userName) }
        try log.userInfo.email.ifNotNil { try container.encode($0, forKey: .userEmail) }

        // Encode network info
        if let networkConnectionInfo = log.networkConnectionInfo {
            try container.encode(networkConnectionInfo.reachability, forKey: .networkReachability)
            try container.encode(networkConnectionInfo.availableInterfaces, forKey: .networkAvailableInterfaces)
            try container.encode(networkConnectionInfo.supportsIPv4, forKey: .networkConnectionSupportsIPv4)
            try container.encode(networkConnectionInfo.supportsIPv6, forKey: .networkConnectionSupportsIPv6)
            try container.encode(networkConnectionInfo.isExpensive, forKey: .networkConnectionIsExpensive)
            try networkConnectionInfo.isConstrained.ifNotNil {
                try container.encode($0, forKey: .networkConnectionIsConstrained)
            }
        }

        // Encode mobile carrier info
        if let carrierInfo = log.mobileCarrierInfo {
            try carrierInfo.carrierName.ifNotNil {
                try container.encode($0, forKey: .mobileNetworkCarrierName)
            }
            try carrierInfo.carrierISOCountryCode.ifNotNil {
                try container.encode($0, forKey: .mobileNetworkCarrierISOCountryCode)
            }
            try container.encode(carrierInfo.radioAccessTechnology, forKey: .mobileNetworkCarrierRadioTechnology)
            try container.encode(carrierInfo.carrierAllowsVOIP, forKey: .mobileNetworkCarrierAllowsVoIP)
        }

        // Encode attributes...
        var attributesContainer = encoder.container(keyedBy: DynamicCodingKey.self)

        // 1. user info attributes
        try log.userInfo.extraInfo.forEach {
            let key = DynamicCodingKey("usr.\($0)")
            try attributesContainer.encode(CodableValue($1), forKey: key)
        }

        // 2. user attributes
        let encodableUserAttributes = Dictionary(
            uniqueKeysWithValues: log.attributes.userAttributes.map { name, value in (name, CodableValue(value)) }
        )
        try encodableUserAttributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }

        // 3. internal attributes
        if let internalAttributes = log.attributes.internalAttributes {
            let encodableInternalAttributes = Dictionary(
                uniqueKeysWithValues: internalAttributes.map { name, value in (name, CodableValue(value)) }
            )
            try encodableInternalAttributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }
        }

        // Encode tags
        var tags = log.tags ?? []
        tags.append("env:\(log.environment)") // include default tag
        let tagsString = tags.joined(separator: ",")
        try container.encode(tagsString, forKey: .tags)
    }
}
