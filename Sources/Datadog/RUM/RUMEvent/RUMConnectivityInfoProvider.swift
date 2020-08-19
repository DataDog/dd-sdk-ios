/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Reduces the values from shared `NetworkConnectionInfoProvider` and `CarrierInfoProvider` to `RUMConnectivity` format.
internal struct RUMConnectivityInfoProvider {
    /// Shared network connection info provider.
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    /// Shared mobile carrier info provider.
    let carrierInfoProvider: CarrierInfoProviderType

    var current: RUMConnectivity? {
        guard let networkInfo = networkConnectionInfoProvider.current else {
            return nil
        }
        let carrierInfo = carrierInfoProvider.current

        return RUMConnectivity(
            status: connectivityStatus(for: networkInfo),
            interfaces: connectivityInterfaces(for: networkInfo),
            cellular: carrierInfo.flatMap { connectivityCellularInfo(for: $0) }
        )
    }

    // MARK: - Private

    private func connectivityStatus(for networkInfo: NetworkConnectionInfo) -> RUMStatus {
        switch networkInfo.reachability {
        case .yes:   return .connected
        case .maybe: return .maybe
        case .no:    return .notConnected
        }
    }

    private func connectivityInterfaces(for networkInfo: NetworkConnectionInfo) -> [RUMInterface] {
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

    private func connectivityCellularInfo(for carrierInfo: CarrierInfo) -> RUMCellular {
        return .init(
            technology: carrierInfo.radioAccessTechnology.rawValue,
            carrierName: carrierInfo.carrierName
        )
    }
}
