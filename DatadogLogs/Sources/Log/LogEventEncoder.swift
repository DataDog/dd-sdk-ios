/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `Encodable` representation of log. It gets sanitized before encoding.
/// All mutable properties are subject of sanitization.
public struct LogEvent: Encodable {
    /// The Log event status definitions.
    public enum Status: String, Encodable, CaseIterable, Equatable {
        case debug
        case info
        case notice
        case warn
        case error
        case critical
        case emergency
    }

    /// Custom attributes associated with a the log event.
    public struct Attributes {
        /// List of log attribute keys used to establish the link between the Log event and the RUM session that it was collected within.
        /// Those keys are recognised by Datadog app and used to render the link in web UI.
        internal enum RUM {
            /// Key referencing the RUM applicaiton ID.
            static let applicationID = "application_id"
            /// Key referencing the RUM session ID.
            static let sessionID = "session_id"
            /// Key referencing the RUM view ID.
            static let viewID = "view.id"
            /// Key referencing the RUM action ID.
            static let actionID = "user_action.id"
        }

        /// List of log attribute keys used to establish the link between the Log event and the Tracing span that it was collected within.
        /// Those keys are recognised by Datadog app and used to render the link in web UI.
        internal enum Trace {
            /// Key referencing the trace ID.
            static let traceID = "dd.trace_id"
            /// Key referencing the span ID.
            static let spanID = "dd.span_id"
        }

        /// Log custom attributes, They are subject for sanitization.
        public var userAttributes: [String: Encodable]
        /// Log attributes added internally by the SDK. They are not a subject for sanitization.
        internal let internalAttributes: [String: Encodable]?
    }

    /// Error description associated with a log event.
    public struct Error {
        /// Description of BinaryImage (used for symbolicaiton of stack traces)
        public struct BinaryImage: Codable {
            /// CPU architecture from the library.
            public let arch: String?

            /// Determines if it's a system or user library.
            public let isSystem: Bool

            /// Library's load address (hexadecimal).
            public let loadAddress: String?

            /// Max value from the library address range (hexadecimal).
            public let maxAddress: String?

            /// Name of the library.
            public let name: String

            /// Build UUID that uniquely identifies the binary image.
            public let uuid: String

            enum CodingKeys: String, CodingKey {
                case arch = "arch"
                case isSystem = "is_system"
                case loadAddress = "load_address"
                case maxAddress = "max_address"
                case name = "name"
                case uuid = "uuid"
            }
        }

        /// The Log error kind
        public var kind: String?
        /// The Log error message
        public var message: String?
        /// The Log error stack
        public var stack: String?
        /// The Log error source_type. Used by cross platform SDKs
        public var sourceType: String = "ios"
        /// The custom fingerprint supplied for this error, if any
        public var fingerprint: String?
        /// Binary images needed to decode the provided stack (if any)
        public var binaryImages: [BinaryImage]?
    }

    /// Datadog specific attributes.
    public struct Dd: Codable {
        /// Device information
        public struct Device: Codable {
            /// The CPU architecture of the device. Used to symbolication and deobfuscation.
            public let architecture: String
        }
        /// Device with the architecture info
        public let device: Device
    }

    /// The log's timestamp
    public let date: Date
    /// The log status
    public let status: Status
    /// The log message
    public var message: String
    /// The associated log error
    public var error: Error?
    /// The service name configured for Logs.
    public let serviceName: String
    /// The current log environment.
    public let environment: String
    /// The configured logger name.
    public let loggerName: String
    /// The current logger version.
    public let loggerVersion: String
    /// The thread's name this log event has been sent from.
    public let threadName: String?
    /// The current application version.
    public let applicationVersion: String
    /// The current application build number.
    public let applicationBuildNumber: String
    /// The id of the current build (used for some cross platform frameworks)
    public let buildId: String?
    /// The variant of the current build (used in some cross platform frameworks)
    public let variant: String?
    /// Datadog specific attributes
    public let dd: Dd
    /// Device information
    public let device: Device
    /// Operating System information
    public let os: OperatingSystem
    /// Custom user information configured globally for the SDK.
    public var userInfo: UserInfo
    /// Custom account information configured globally for the SDK.
    public var accountInfo: AccountInfo?
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
        case environment = "env"
        case tags = "ddtags"

        // MARK: - Error

        case errorKind = "error.kind"
        case errorMessage = "error.message"
        case errorStack = "error.stack"
        case errorSourceType = "error.source_type"
        case errorFingerprint = "error.fingerprint"
        case errorBinaryImages = "error.binary_images"

        // MARK: - Application info

        case applicationVersion = "version"
        case applicationBuildNumber = "build_version"
        case buildId = "build_id"

        // MARK: - Dd info

        case dd = "_dd"

        // MARK: - Device info
        case device
        case os

        // MARK: - Logger info

        case loggerName = "logger.name"
        case loggerVersion = "logger.version"
        case threadName = "logger.thread_name"

        // MARK: - User info

        case userAnonymousId = "usr.anonymous_id"
        case userId = "usr.id"
        case userName = "usr.name"
        case userEmail = "usr.email"

        // MARK: - Account info

        case accountId = "account.id"
        case accountName = "account.name"

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
            try container.encode(someError.sourceType, forKey: .errorSourceType)
            try container.encode(someError.fingerprint, forKey: .errorFingerprint)
            if let binaryImages = someError.binaryImages {
                try container.encode(binaryImages, forKey: .errorBinaryImages)
            }
        }

        // Encode logger info
        try container.encode(log.loggerName, forKey: .loggerName)
        try container.encode(log.loggerVersion, forKey: .loggerVersion)
        try container.encode(log.threadName, forKey: .threadName)

        // Encode application info
        try container.encode(log.applicationVersion, forKey: .applicationVersion)
        try container.encode(log.applicationBuildNumber, forKey: .applicationBuildNumber)
        if let buildId = log.buildId {
            try container.encode(buildId, forKey: .buildId)
        }

        try container.encode(log.dd, forKey: .dd)
        try container.encode(log.device, forKey: .device)
        try container.encode(log.os, forKey: .os)

        // Encode user info
        try log.userInfo.id.ifNotNil { try container.encode($0, forKey: .userId) }
        try log.userInfo.name.ifNotNil { try container.encode($0, forKey: .userName) }
        try log.userInfo.email.ifNotNil { try container.encode($0, forKey: .userEmail) }
        try log.userInfo.anonymousId.ifNotNil { try container.encode($0, forKey: .userAnonymousId) }

        // Encode account info
        if let accountInfo = log.accountInfo {
            try container.encode(accountInfo.id, forKey: .accountId)
            try accountInfo.name.ifNotNil { try container.encode($0, forKey: .accountName) }
        }

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
            try attributesContainer.encode(AnyEncodable($1), forKey: key)
        }

        // 2. account info attributes
        try log.accountInfo?.extraInfo.forEach {
            let key = DynamicCodingKey("account.\($0)")
            try attributesContainer.encode(AnyEncodable($1), forKey: key)
        }

        // 3. user attributes
        let encodableUserAttributes = Dictionary(
            uniqueKeysWithValues: log.attributes.userAttributes.map { name, value in (name, AnyEncodable(value)) }
        )
        try encodableUserAttributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }

        // 4. internal attributes
        if let internalAttributes = log.attributes.internalAttributes {
            let encodableInternalAttributes = Dictionary(
                uniqueKeysWithValues: internalAttributes.map { name, value in (name, AnyEncodable(value)) }
            )
            try encodableInternalAttributes.forEach { try attributesContainer.encode($0.value, forKey: DynamicCodingKey($0.key)) }
        }

        // Encode tags
        var tags = log.tags ?? []
        tags.append("service:\(log.serviceName)") // include default service tag
        tags.append("env:\(log.environment)") // include default env tag
        tags.append("version:\(log.applicationVersion)") // include default version tag
        if let variant = log.variant {
            tags.append("variant:\(variant)")
        }
        let tagsString = tags.joined(separator: ",")
        try container.encode(tagsString, forKey: .tags)
    }
}
