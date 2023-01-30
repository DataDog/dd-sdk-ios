/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUMConnectivity {
    init?(context: DatadogContext) {
        self.init(
            networkInfo: context.networkConnectionInfo,
            carrierInfo: context.carrierInfo
        )
    }

    init?(networkInfo: NetworkConnectionInfo?, carrierInfo: CarrierInfo?) {
        guard let networkInfo = networkInfo else {
            return nil
        }

        self.init(
            cellular: carrierInfo.flatMap { RUMConnectivity.connectivityCellularInfo(for: $0) },
            interfaces: RUMConnectivity.connectivityInterfaces(for: networkInfo),
            status: RUMConnectivity.connectivityStatus(for: networkInfo)
        )
    }

    // MARK: - Private

    private static func connectivityStatus(for networkInfo: NetworkConnectionInfo) -> RUMConnectivity.Status {
        switch networkInfo.reachability {
        case .yes:   return .connected
        case .maybe: return .maybe
        case .no:    return .notConnected
        }
    }

    private static func connectivityInterfaces(for networkInfo: NetworkConnectionInfo) -> [RUMConnectivity.Interfaces] {
        guard let availableInterfaces = networkInfo.availableInterfaces, !availableInterfaces.isEmpty else {
            return [.none]
        }

        return availableInterfaces.map { interface in
            switch interface {
            case .cellular:         return .cellular
            case .wifi:             return .wifi
            case .wiredEthernet:    return .ethernet
            case .loopback, .other: return .other
            }
        }
    }

    private static func connectivityCellularInfo(for carrierInfo: CarrierInfo) -> RUMConnectivity.Cellular {
        return RUMConnectivity.Cellular(
            carrierName: carrierInfo.carrierName,
            technology: carrierInfo.radioAccessTechnology.rawValue
        )
    }
}
