/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describes current Datadog SDK context, so the app state information can be attached to
/// the crash report and retrieved back when the application is started again.
///
/// Note: as it gets saved along with the crash report during process interruption, it's good
/// to keep this data well-packed and as small as possible.
internal struct CrashContext: Codable {
    // MARK: - Initialization

    init(
        lastTrackingConsent: TrackingConsent,
        lastUserInfo: UserInfo,
        lastRUMViewEvent: RUMViewEvent?,
        lastNetworkConnectionInfo: NetworkConnectionInfo?,
        lastCarrierInfo: CarrierInfo?,
        lastRUMSessionState: RUMSessionState?,
        lastIsAppInForeground: Bool
    ) {
        self.codableTrackingConsent = .init(from: lastTrackingConsent)
        self.codableLastUserInfo = .init(from: lastUserInfo)
        self.lastRUMViewEvent = lastRUMViewEvent
        self.codableLastNetworkConnectionInfo = lastNetworkConnectionInfo.flatMap { .init(from: $0) }
        self.codableLastCarrierInfo = lastCarrierInfo.flatMap { .init(from: $0) }
        self.lastRUMSessionState = lastRUMSessionState
        self.lastIsAppInForeground = lastIsAppInForeground
    }

    // MARK: - Codable values

    private var codableTrackingConsent: CodableTrackingConsent
    private var codableLastUserInfo: CodableUserInfo?
    private var codableLastNetworkConnectionInfo: CodableNetworkConnectionInfo?
    private var codableLastCarrierInfo: CodableCarrierInfo?

    enum CodingKeys: String, CodingKey {
        case codableTrackingConsent = "ctc"
        case codableLastUserInfo = "lui"
        case codableLastNetworkConnectionInfo = "lni"
        case codableLastCarrierInfo = "lci"
        case lastRUMViewEvent = "lre"
        case lastRUMSessionState = "rst"
        case lastIsAppInForeground = "aif"
    }

    // MARK: - Setters & Getters using managed types

    var lastTrackingConsent: TrackingConsent {
        set { codableTrackingConsent = CodableTrackingConsent(from: newValue) }
        get { codableTrackingConsent.managedValue }
    }

    var lastUserInfo: UserInfo? {
        set { codableLastUserInfo = newValue.flatMap { CodableUserInfo(from: $0) } }
        get { codableLastUserInfo?.managedValue }
    }

    var lastNetworkConnectionInfo: NetworkConnectionInfo? {
        set { codableLastNetworkConnectionInfo = newValue.flatMap { CodableNetworkConnectionInfo(from: $0) } }
        get { codableLastNetworkConnectionInfo?.managedValue }
    }

    var lastCarrierInfo: CarrierInfo? {
        set { codableLastCarrierInfo = newValue.flatMap { CodableCarrierInfo(from: $0) } }
        get { codableLastCarrierInfo?.managedValue }
    }

    // MARK: - Direct Codable values

    var lastRUMViewEvent: RUMViewEvent?

    /// State of the last RUM session in crashed app process.
    var lastRUMSessionState: RUMSessionState?

    /// The last _"Is app in foreground?"_ information from crashed app process.
    var lastIsAppInForeground: Bool
}

// MARK: - Bridging managed types to Codable representation

/// Codable representation of the public `TrackingConsent`. Uses `Int8` for optimized packing.
private enum CodableTrackingConsent: Int8, Codable {
    case granted
    case notGranted
    case pending

    init(from managedValue: TrackingConsent) {
        switch managedValue {
        case .pending: self = .pending
        case .granted: self = .granted
        case .notGranted: self = .notGranted
        }
    }

    var managedValue: TrackingConsent {
        switch self {
        case .pending: return .pending
        case .granted: return .granted
        case .notGranted: return .notGranted
        }
    }
}

private struct CodableUserInfo: Codable {
    private let id: String?
    private let name: String?
    private let email: String?
    private let extraInfo: [AttributeKey: AttributeValue]

    init(from managedValue: UserInfo) {
        self.id = managedValue.id
        self.name = managedValue.name
        self.email = managedValue.email
        self.extraInfo = managedValue.extraInfo
    }

    var managedValue: UserInfo {
        return .init(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "nm"
        case email = "em"
        case extraInfo = "ei"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.extraInfo = try container.decode([String: CodableValue].self, forKey: .extraInfo)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let encodedExtraInfo = extraInfo.mapValues { CodableValue($0) }

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(email, forKey: .email)
        try container.encode(encodedExtraInfo, forKey: .extraInfo)
    }
}

private struct CodableNetworkConnectionInfo: Codable {
    private let reachability: NetworkConnectionInfo.Reachability
    private let availableInterfaces: [NetworkConnectionInfo.Interface]?
    private let supportsIPv4: Bool?
    private let supportsIPv6: Bool?
    private let isExpensive: Bool?
    private let isConstrained: Bool?

    init(from managedValue: NetworkConnectionInfo) {
        self.reachability = managedValue.reachability
        self.availableInterfaces = managedValue.availableInterfaces
        self.supportsIPv4 = managedValue.supportsIPv4
        self.supportsIPv6 = managedValue.supportsIPv6
        self.isExpensive = managedValue.isExpensive
        self.isConstrained = managedValue.isConstrained
    }

    var managedValue: NetworkConnectionInfo {
        return .init(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case reachability = "rcb"
        case availableInterfaces = "abi"
        case supportsIPv4 = "si4"
        case supportsIPv6 = "si6"
        case isExpensive = "ise"
        case isConstrained = "isc"
    }
}

private struct CodableCarrierInfo: Codable {
    private let carrierName: String?
    private let carrierISOCountryCode: String?
    private let carrierAllowsVOIP: Bool
    private let radioAccessTechnology: CarrierInfo.RadioAccessTechnology

    init(from managedValue: CarrierInfo) {
        self.carrierName = managedValue.carrierName
        self.carrierISOCountryCode = managedValue.carrierISOCountryCode
        self.carrierAllowsVOIP = managedValue.carrierAllowsVOIP
        self.radioAccessTechnology = managedValue.radioAccessTechnology
    }

    var managedValue: CarrierInfo {
        return .init(
            carrierName: carrierName,
            carrierISOCountryCode: carrierISOCountryCode,
            carrierAllowsVOIP: carrierAllowsVOIP,
            radioAccessTechnology: radioAccessTechnology
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case carrierName = "crn"
        case carrierISOCountryCode = "cri"
        case carrierAllowsVOIP = "cra"
        case radioAccessTechnology = "rdt"
    }
}
