import Foundation

/// Convenience typealias.
internal typealias BatteryStatus = MobileDevice.BatteryStatus

/// Shared provider to get current `BatteryStatus`.
internal protocol BatteryStatusProviderType {
    var current: BatteryStatus { get }
}

internal class BatteryStatusProvider: BatteryStatusProviderType {
    private let mobileDevice: MobileDevice

    /// `BatteryStatusProvider` can be only instantiated for mobile devices.
    /// SDK does not consider battery status when running on other platforms.
    init(mobileDevice: MobileDevice) {
        self.mobileDevice = mobileDevice
        mobileDevice.enableBatteryStatusMonitoring()
    }

    deinit {
        mobileDevice.resetBatteryStatusMonitoring()
    }

    var current: BatteryStatus { mobileDevice.currentBatteryStatus() }
}
