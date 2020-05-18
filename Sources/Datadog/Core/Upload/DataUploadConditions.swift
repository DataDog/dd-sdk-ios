/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Tells if data upload can be performed based on given system conditions.
internal struct DataUploadConditions {
    struct Constants {
        /// Battery level above which data upload can be performed.
        static let minBatteryLevel: Float = 0.1
    }

    let batteryStatus: BatteryStatusProviderType?
    let networkConnectionInfo: NetworkConnectionInfoProviderType

    func canPerformUpload() -> Bool {
        let batteryStatus = self.batteryStatus?.current
        guard let networkConnectionInfo = self.networkConnectionInfo.current else {
            return false // when `NetworkConnectionInfo` is not yet available
        }

        if let batteryStatus = batteryStatus {
            return shouldUploadFor(networkConnectionInfo: networkConnectionInfo) && shouldUploadFor(batteryStatus: batteryStatus)
        } else {
            return shouldUploadFor(networkConnectionInfo: networkConnectionInfo)
        }
    }

    private func shouldUploadFor(batteryStatus: BatteryStatus) -> Bool {
        let batteryFullOrCharging = batteryStatus.state == .full || batteryStatus.state == .charging
        let batteryLevelIsEnough = batteryStatus.level > Constants.minBatteryLevel
        let isLowPowerModeEnabled = batteryStatus.isLowPowerModeEnabled
        return (batteryLevelIsEnough || batteryFullOrCharging) && !isLowPowerModeEnabled
    }

    private func shouldUploadFor(networkConnectionInfo: NetworkConnectionInfo) -> Bool {
        return networkConnectionInfo.reachability == .yes || networkConnectionInfo.reachability == .maybe
    }
}
