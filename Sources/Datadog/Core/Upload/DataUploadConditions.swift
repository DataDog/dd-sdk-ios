import Foundation

/// Tells if data upload can be performed based on given system conditions.
internal struct DataUploadConditions {
    struct Constants {
        /// Battery level above which data upload can be performed.
        static let minBatteryLevel: Float = 10
    }

    let batteryStatus: BatteryStatusProvider?
    let networkStatus: NetworkStatusProvider

    func canPerformUpload() -> Bool {
        let batteryStatus = self.batteryStatus?.current
        let networkStatus = self.networkStatus.current

        if let batteryStatus = batteryStatus {
            return shouldUploadFor(networkStatus: networkStatus) && shouldUploadFor(batteryStatus: batteryStatus)
        } else {
            return shouldUploadFor(networkStatus: networkStatus)
        }
    }

    private func shouldUploadFor(batteryStatus: BatteryStatus) -> Bool {
        let batteryFullOrCharging = batteryStatus.state == .full || batteryStatus.state == .charging
        let batteryLevelIsEnough = batteryStatus.level > Constants.minBatteryLevel
        let isLowPowerModeEnabled = batteryStatus.isLowPowerModeEnabled
        return (batteryLevelIsEnough || batteryFullOrCharging) && !isLowPowerModeEnabled
    }

    private func shouldUploadFor(networkStatus: NetworkStatus) -> Bool {
        return networkStatus.reachability == .yes || networkStatus.reachability == .maybe
    }
}
