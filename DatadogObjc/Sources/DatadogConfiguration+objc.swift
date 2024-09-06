/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogCore

@objc
public class DDSite: NSObject {
    internal let sdkSite: DatadogSite?

    internal init(sdkSite: DatadogSite?) {
        self.sdkSite = sdkSite
    }

    // MARK: - Public

    @objc
    public static func us1() -> DDSite { .init(sdkSite: .us1) }

    @objc
    public static func us3() -> DDSite { .init(sdkSite: .us3) }

    @objc
    public static func us5() -> DDSite { .init(sdkSite: .us5) }

    @objc
    public static func eu1() -> DDSite { .init(sdkSite: .eu1) }

    @objc
    public static func ap1() -> DDSite { .init(sdkSite: .ap1) }

    @objc
    public static func us1_fed() -> DDSite { .init(sdkSite: .us1_fed) }
}

@objc
public enum DDBatchSize: Int {
    case small
    case medium
    case large

    internal var swiftType: Datadog.Configuration.BatchSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }

    internal init(swiftType: Datadog.Configuration.BatchSize) {
        switch swiftType {
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        }
    }
}

@objc
public enum DDUploadFrequency: Int {
    case frequent
    case average
    case rare
    case none

    internal var swiftType: Datadog.Configuration.UploadFrequency? {
        switch self {
        case .frequent: return .frequent
        case .average: return .average
        case .rare: return .rare
        case .none: return nil
        }
    }

    internal init(swiftType: Datadog.Configuration.UploadFrequency?) {
        switch swiftType {
        case .frequent: self = .frequent
        case .average: self = .average
        case .rare: self = .rare
        case .none: self = .none
        }
    }
}

@objc
public enum DDBatchProcessingLevel: Int {
    case low
    case medium
    case high
    case none

    internal var swiftType: Datadog.Configuration.BatchProcessingLevel? {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case .none: return nil
        }
    }

    internal init(swiftType: Datadog.Configuration.BatchProcessingLevel?) {
        switch swiftType {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .none: self = .none
        }
    }
}

@objc
public class DDTracingHeaderType: NSObject {
    internal let swiftType: TracingHeaderType

    private init(_ swiftType: TracingHeaderType) {
        self.swiftType = swiftType
    }

    @objc public static let datadog = DDTracingHeaderType(.datadog)
    @objc public static let b3multi = DDTracingHeaderType(.b3multi)
    @objc public static let b3 = DDTracingHeaderType(.b3)
    @objc public static let tracecontext = DDTracingHeaderType(.tracecontext)
}

@objc
public protocol DDDataEncryption: AnyObject {
    /// Encrypts given `Data` with user-chosen encryption.
    ///
    /// - Parameter data: Data to encrypt.
    /// - Returns: The encrypted data.
    func encrypt(data: Data) throws -> Data

    /// Decrypts given `Data` with user-chosen encryption.
    ///
    /// Beware that data to decrypt could be encrypted in a previous
    /// app launch, so implementation should be aware of the case when decryption could
    /// fail (for example, key used for encryption is different from key used for decryption, if
    /// they are unique for every app launch).
    ///
    /// - Parameter data: Data to decrypt.
    /// - Returns: The decrypted data.
    func decrypt(data: Data) throws -> Data
}

internal struct DDDataEncryptionBridge: DataEncryption {
    let objcEncryption: DDDataEncryption

    func encrypt(data: Data) throws -> Data {
        return try objcEncryption.encrypt(data: data)
    }

    func decrypt(data: Data) throws -> Data {
        return try objcEncryption.decrypt(data: data)
    }
}

@objc
public protocol DDServerDateProvider: AnyObject {
    /// Start the clock synchronisation with NTP server.
    ///
    /// Calls the `completion` by passing it the server time offset when the synchronization succeeds or`nil` if it fails.
    func synchronize(update: @escaping (TimeInterval) -> Void)
}

internal struct DDServerDateProviderBridge: ServerDateProvider {
    let objcProvider: DDServerDateProvider

    func synchronize(update: @escaping (TimeInterval) -> Void) {
        objcProvider.synchronize(update: update)
    }
}

@objc
public class DDConfiguration: NSObject {
    internal var sdkConfiguration: Datadog.Configuration

    /// Either the RUM client token (which supports RUM, Logging and APM) or regular client token, only for Logging and APM.
    @objc public var clientToken: String? {
        get { sdkConfiguration.clientToken }
        set { sdkConfiguration.clientToken = newValue }
    }

    /// The environment name which will be sent to Datadog. This can be used
    /// To filter events on different environments (e.g. "staging" or "production").
    @objc public var env: String? {
        get { sdkConfiguration.env }
        set { sdkConfiguration.env = newValue }
    }

    /// The Datadog server site where data is sent.
    ///
    /// Default value is `.us1`.
    @objc public var site: DDSite? {
        get { DDSite(sdkSite: sdkConfiguration.site) }
        set { sdkConfiguration.site = newValue?.sdkSite }
    }

    /// The service name associated with data send to Datadog.
    ///
    /// Default value is set to application bundle identifier.
    @objc public var service: String? {
        get { sdkConfiguration.service }
        set { sdkConfiguration.service = newValue }
    }

    /// The preferred size of batched data uploaded to Datadog servers.
    /// This value impacts the size and number of requests performed by the SDK.
    ///
    /// `.medium` by default.
    @objc public var batchSize: DDBatchSize {
        get { DDBatchSize(swiftType: sdkConfiguration.batchSize) }
        set { sdkConfiguration.batchSize = newValue.swiftType }
    }

    /// The preferred frequency of uploading data to Datadog servers.
    /// This value impacts the frequency of performing network requests by the SDK.
    ///
    /// `.average` by default.
    @objc public var uploadFrequency: DDUploadFrequency {
        get { DDUploadFrequency(swiftType: sdkConfiguration.uploadFrequency) }
        set { sdkConfiguration.uploadFrequency = newValue.swiftType }
    }

    /// 
    @objc public var batchProcessingLevel: DDBatchProcessingLevel {
        get { DDBatchProcessingLevel(swiftType: sdkConfiguration.batchProcessingLevel) }
        set { sdkConfiguration.batchProcessingLevel = newValue.swiftType }
    }

    /// Proxy configuration attributes.
    /// This can be used to a enable a custom proxy for uploading tracked data to Datadog's intake.
    @objc public var proxyConfiguration: [AnyHashable: Any]? {
        get { sdkConfiguration.proxyConfiguration }
        set { sdkConfiguration.proxyConfiguration = newValue }
    }

    /// Sets Data encryption to use for on-disk data persistency by providing an object
    /// complying with `DataEncryption` protocol.
    @objc
    public func setEncryption(_ encryption: DDDataEncryption) {
        sdkConfiguration.encryption = DDDataEncryptionBridge(objcEncryption: encryption)
    }

    /// A custom NTP synchronization interface.
    ///
    /// By default, the Datadog SDK synchronizes with dedicated NTP pools provided by the
    /// https://www.ntppool.org/ . Using different pools or setting a no-op `ServerDateProvider`
    /// implementation will result in desynchronization of the SDK instance and the Datadog servers.
    /// This can lead to significant time shift in RUM sessions or distributed traces.
    @objc
    public func setServerDateProvider(_ serverDateProvider: DDServerDateProvider) {
        sdkConfiguration.serverDateProvider = DDServerDateProviderBridge(objcProvider: serverDateProvider)
    }

    /// The bundle object that contains the current executable.
    @objc public var bundle: Bundle {
        get { sdkConfiguration.bundle }
        set { sdkConfiguration.bundle = newValue }
    }

    /// Sets additional configuration attributes.
    /// This can be used to tweak internal features of the SDK and shouldn't be considered as a part of public API.
    @objc public var additionalConfiguration: [String: Any] {
        get { sdkConfiguration._internal.additionalConfiguration }
        set { sdkConfiguration._internal_mutation { $0.additionalConfiguration = newValue } }
    }

    /// Creates a Datadog SDK Configuration object.
    ///
    /// - Parameters:
    ///   - clientToken:    Either the RUM client token (which supports RUM, Logging and APM) or regular client token,
    ///                     only for Logging and APM.
    ///
    ///   - env:    The environment name which will be sent to Datadog. This can be used
    ///             To filter events on different environments (e.g. "staging" or "production").
    @objc
    public init(clientToken: String, env: String) {
        sdkConfiguration = .init(clientToken: clientToken, env: env)
    }
}
