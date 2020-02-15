import CoreTelephony

/// Network connection details specific to cellular radio access.
internal struct CarrierInfo {
    // swiftlint:disable identifier_name
    enum RadioAccessTechnology: String, Encodable {
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

    let carrierName: String?
    let carrierISOCountryCode: String?
    let carrierAllowsVOIP: Bool
    let radioAccessTechnology: RadioAccessTechnology
}

internal protocol CarrierInfoProviderType {
    var current: CarrierInfo? { get }
}

internal class CarrierInfoProvider: CarrierInfoProviderType {
    #if os(iOS)
    private let networkInfo: CTTelephonyNetworkInfo

    init(networkInfo: CTTelephonyNetworkInfo) {
        self.networkInfo = networkInfo
    }
    #endif

    static func getIfAvailable() -> CarrierInfoProvider? {
        #if os(iOS)
        return CarrierInfoProvider(networkInfo: CTTelephonyNetworkInfo())
        #else
        return nil
        #endif
    }

    var current: CarrierInfo? {
        #if os(iOS)
        if let cellularProviderKey = networkInfo.serviceCurrentRadioAccessTechnology?.keys.first {
            guard let radioAccessTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[cellularProviderKey] else {
                return nil
            }
            guard let currentCTCarrier = networkInfo.serviceSubscriberCellularProviders?[cellularProviderKey] else {
                return nil
            }

            return CarrierInfo(
                carrierName: currentCTCarrier.carrierName,
                carrierISOCountryCode: currentCTCarrier.isoCountryCode,
                carrierAllowsVOIP: currentCTCarrier.allowsVOIP,
                radioAccessTechnology: .init(ctRadioAccessTechnologyConstant: radioAccessTechnology)
            )
        } else {
            // Presumably:
            // * The device is in airplane mode.
            // * There is no SIM card in the device.
            // * The device is outside of cellular service range.
            return nil
        }
        #else
        return nil // not available on this platform
        #endif
    }
}

#if os(iOS)
extension CarrierInfo.RadioAccessTechnology {
    init(ctRadioAccessTechnologyConstant: String) {
        switch ctRadioAccessTechnologyConstant {
        case CTRadioAccessTechnologyGPRS: self = .GPRS
        case CTRadioAccessTechnologyEdge: self = .Edge
        case CTRadioAccessTechnologyWCDMA: self = .WCDMA
        case CTRadioAccessTechnologyHSDPA: self = .HSDPA
        case CTRadioAccessTechnologyHSUPA: self = .HSUPA
        case CTRadioAccessTechnologyCDMA1x: self = .CDMA1x
        case CTRadioAccessTechnologyCDMAEVDORev0: self = .CDMAEVDORev0
        case CTRadioAccessTechnologyCDMAEVDORevA: self = .CDMAEVDORevA
        case CTRadioAccessTechnologyCDMAEVDORevB: self = .CDMAEVDORevB
        case CTRadioAccessTechnologyeHRPD: self = .eHRPD
        case CTRadioAccessTechnologyLTE: self = .LTE
        default: self = .unknown
        }
    }
}
#endif
