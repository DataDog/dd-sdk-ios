/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Tells if data upload can be performed based on given system conditions.
internal struct DataUploadConditions {
    enum Blocker {
        case battery(level: Int, state: BatteryStatus.State)
        case lowPowerModeOn
        case networkReachability(description: String)
    }

    struct Constants {
        /// Battery level above which data upload can be performed.
        static let minBatteryLevel: Float = 0.1
    }

    let batteryStatus: BatteryStatusProviderType?
    let networkConnectionInfo: NetworkConnectionInfoProviderType

    func blockersForUpload() -> [Blocker] {
        let batteryStatus = self.batteryStatus?.current
        guard let networkConnectionInfo = self.networkConnectionInfo.current else {
            // when `NetworkConnectionInfo` is not yet available
            return [.networkReachability(description: "unknown")]
        }

        if let batteryStatus = batteryStatus {
            return blockersForUploadWith(networkConnectionInfo) + blockersForUploadWith(batteryStatus)
        } else {
            return blockersForUploadWith(networkConnectionInfo)
        }
    }

    private func blockersForUploadWith(_ batteryStatus: BatteryStatus) -> [Blocker] {
        let state = batteryStatus.state
        if state == .unknown {
            // Note: in RUMS-132 we got the report on `.unknown` battery state reporing `-1` battery level on iPad device
            // plugged to Mac through lightning cable. As `.unkown` may lead to other unreliable values,
            // it seems safer to arbitrary allow uploads in such case.
            return []
        }

        var blockers = [Blocker]()
        let batteryFullOrCharging = state == .full || state == .charging
        let batteryLevelIsEnough = batteryStatus.level > Constants.minBatteryLevel
        if !(batteryFullOrCharging || batteryLevelIsEnough) {
            blockers.append(
                .battery(
                    level: Int(batteryStatus.level * 100),
                    state: batteryStatus.state
                )
            )
        }

        if batteryStatus.isLowPowerModeEnabled {
            blockers.append(.lowPowerModeOn)
        }

        return blockers
    }

    private func blockersForUploadWith(_ networkConnectionInfo: NetworkConnectionInfo) -> [Blocker] {
        let networkIsReachable = networkConnectionInfo.reachability == .yes || networkConnectionInfo.reachability == .maybe
        return networkIsReachable ? [] : [.networkReachability(description: networkConnectionInfo.reachability.rawValue)]
    }
}
