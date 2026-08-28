/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Carrier details specific to cellular radio access.
///
/// - Note: Only available on iOS versions below 16. Apple deprecated the underlying Core Telephony
///   APIs (`CTCarrier`) in iOS 16 with no replacement and confirmed they always return placeholder
///   ("--") or empty values from that version onward, so `CarrierInfo` is never published on iOS 16+.
///   ref.: https://forums.developer.apple.com/forums/thread/714876
public struct CarrierInfo: Codable, Equatable {
    // swiftlint:disable identifier_name
    public enum RadioAccessTechnology: String, Codable, CaseIterable {
        case GPRS
        case Edge
        case WCDMA
        case HSDPA
        case HSUPA
        case CDMA1x
        case CDMAEVDORev0
        case CDMAEVDORevA
        case CDMAEVDORevB
        case eHRPD
        case LTE
        case unknown
    }
    // swiftlint:enable identifier_name

    /// The name of the user’s home cellular service provider.
    public let carrierName: String?
    /// The ISO country code for the user’s cellular service provider.
    public let carrierISOCountryCode: String?
    /// Indicates if the carrier allows making VoIP calls on its network.
    public let carrierAllowsVOIP: Bool
    /// The radio access technology used for cellular connection.
    public let radioAccessTechnology: RadioAccessTechnology

    public init(
        carrierName: String?,
        carrierISOCountryCode: String?,
        carrierAllowsVOIP: Bool,
        radioAccessTechnology: RadioAccessTechnology
    ) {
        self.carrierName = carrierName
        self.carrierISOCountryCode = carrierISOCountryCode
        self.carrierAllowsVOIP = carrierAllowsVOIP
        self.radioAccessTechnology = radioAccessTechnology
    }
}
