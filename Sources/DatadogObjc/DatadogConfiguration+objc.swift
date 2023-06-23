/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import Datadog

@objc
public class DDEndpoint: NSObject {
    internal let sdkEndpoint: DatadogSite

    internal init(sdkEndpoint: DatadogSite) {
        self.sdkEndpoint = sdkEndpoint
    }

    // MARK: - Public

    @objc
    public static func us1() -> DDEndpoint { .init(sdkEndpoint: .us1) }

    @objc
    public static func us3() -> DDEndpoint { .init(sdkEndpoint: .us3) }

    @objc
    public static func us5() -> DDEndpoint { .init(sdkEndpoint: .us5) }

    @objc
    public static func eu1() -> DDEndpoint { .init(sdkEndpoint: .eu1) }

    @objc
    public static func ap1() -> DDEndpoint { .init(sdkEndpoint: .ap1) }

    @objc
    public static func us1_fed() -> DDEndpoint { .init(sdkEndpoint: .us1_fed) }

    @objc
    public static func eu() -> DDEndpoint { .init(sdkEndpoint: .eu1) }

    @objc
    public static func us() -> DDEndpoint { .init(sdkEndpoint: .us1) }

    @objc
    public static func gov() -> DDEndpoint { .init(sdkEndpoint: .us1_fed) }
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
}

@objc
public enum DDUploadFrequency: Int {
    case frequent
    case average
    case rare

    internal var swiftType: Datadog.Configuration.UploadFrequency {
        switch self {
        case .frequent: return .frequent
        case .average: return .average
        case .rare: return .rare
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
    internal let sdkConfiguration: Datadog.Configuration

    internal init(sdkConfiguration: Datadog.Configuration) {
        self.sdkConfiguration = sdkConfiguration
    }

    // MARK: - Public

    @objc
    public static func builder(clientToken: String, environment: String) -> DDConfigurationBuilder {
        return DDConfigurationBuilder(
            sdkBuilder: Datadog.Configuration.builderUsing(clientToken: clientToken, environment: environment)
        )
    }
}

@objc
public class DDConfigurationBuilder: NSObject {
    internal let sdkBuilder: Datadog.Configuration.Builder

    internal init(sdkBuilder: Datadog.Configuration.Builder) {
        self.sdkBuilder = sdkBuilder
    }

    // MARK: - Public

    @objc
    public func enableTracing(_ enabled: Bool) {
        _ = sdkBuilder.enableTracing(enabled)
    }

    @objc
    public func set(endpoint: DDEndpoint) {
        _ = sdkBuilder.set(endpoint: endpoint.sdkEndpoint)
    }

    /// Sets a custom NTP synchronization interface.
    ///
    /// By default, the Datadog SDK synchronizes with dedicated NTP pools provided by the
    /// https://www.ntppool.org/ . Using different pools or setting a no-op `DDServerDateProvider`
    /// implementation will result in desynchronization of the SDK instance and the Datadog servers.
    /// This can lead to significant time shift in RUM sessions or distributed traces.
    ///
    /// - Parameter serverDateProvider: An object that complies with `DDServerDateProvider`
    ///                                 for provider clock synchronisation.
    @objc
    public func set(serverDateProvider: DDServerDateProvider) {
        _ = sdkBuilder.set(serverDateProvider: DDServerDateProviderBridge(objcProvider: serverDateProvider))
    }

    @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
    @objc
    public func set(tracedHosts: Set<String>) {
        track(firstPartyHosts: tracedHosts)
    }

    @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
    @objc
    public func track(firstPartyHosts: Set<String>) {
        trackURLSession(firstPartyHosts: firstPartyHosts)
    }

    @objc
    public func trackURLSession(firstPartyHosts: Set<String>) {
        _ = sdkBuilder.trackURLSession(firstPartyHosts: firstPartyHosts)
    }

    @objc
    public func trackURLSession(firstPartyHostsWithHeaderTypes: [String: Set<DDTracingHeaderType>]) {
        _ = sdkBuilder.trackURLSession(firstPartyHostsWithHeaderTypes: firstPartyHostsWithHeaderTypes.mapValues { tracingHeaderTypes in
            return Set(tracingHeaderTypes.map { $0.swiftType })
        })
    }

    @objc
    public func set(serviceName: String) {
        _ = sdkBuilder.set(serviceName: serviceName)
    }

    @objc
    public func set(tracingSamplingRate: Float) {
        _ = sdkBuilder.set(tracingSamplingRate: tracingSamplingRate)
    }

    @objc
    public func set(batchSize: DDBatchSize) {
        _ = sdkBuilder.set(batchSize: batchSize.swiftType)
    }

    @objc
    public func set(uploadFrequency: DDUploadFrequency) {
        _ = sdkBuilder.set(uploadFrequency: uploadFrequency.swiftType)
    }

    @objc
    public func set(additionalConfiguration: [String: Any]) {
        _ = sdkBuilder.set(additionalConfiguration: additionalConfiguration)
    }

    @objc
    public func set(proxyConfiguration: [AnyHashable: Any]) {
        _ = sdkBuilder.set(proxyConfiguration: proxyConfiguration)
    }

    @objc
    public func set(encryption: DDDataEncryption) {
        _ = sdkBuilder.set(encryption: DDDataEncryptionBridge(objcEncryption: encryption))
    }

    @objc
    public func build() -> DDConfiguration {
        return DDConfiguration(sdkConfiguration: sdkBuilder.build())
    }
}
