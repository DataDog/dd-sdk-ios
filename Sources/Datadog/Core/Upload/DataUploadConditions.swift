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
        let networkConnectionInfo = self.networkConnectionInfo.current

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
