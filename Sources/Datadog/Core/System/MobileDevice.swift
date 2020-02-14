import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Describes current mobile device.
internal class MobileDevice {
    // MARK: - Info

    let model: String
    let osName: String
    let osVersion: String

    // MARK: - Battery status monitoring

    struct BatteryStatus {
        enum State: Equatable {
            case unknown
            case unplugged
            case charging
            case full
        }

        let state: State
        let level: Float
        let isLowPowerModeEnabled: Bool
    }

    /// Enables battery status monitoring.
    let enableBatteryStatusMonitoring: () -> Void
    /// Resets battery status monitoring.
    let resetBatteryStatusMonitoring: () -> Void
    /// Returns current `BatteryStatus`.
    let currentBatteryStatus: () -> BatteryStatus

    init(
        model: String,
        osName: String,
        osVersion: String,
        enableBatteryStatusMonitoring: @escaping () -> Void,
        resetBatteryStatusMonitoring: @escaping () -> Void,
        currentBatteryStatus: @escaping () -> BatteryStatus
    ) {
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
        self.enableBatteryStatusMonitoring = enableBatteryStatusMonitoring
        self.resetBatteryStatusMonitoring = resetBatteryStatusMonitoring
        self.currentBatteryStatus = currentBatteryStatus
    }

    /// Returns current mobile device  if `UIDevice` is available on this platform.
    /// On other platforms returns `nil`.
    static var current: MobileDevice? {
        #if canImport(UIKit)
        let wasBatteryMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled

        return MobileDevice(
            model: UIDevice.current.model,
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            enableBatteryStatusMonitoring: { UIDevice.current.isBatteryMonitoringEnabled = true },
            resetBatteryStatusMonitoring: { UIDevice.current.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled },
            currentBatteryStatus: {
                return BatteryStatus(
                    state: toBatteryState(UIDevice.current.batteryState),
                    level: UIDevice.current.batteryLevel,
                    isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
                )
            }
        )
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private static func toBatteryState(_ uiDeviceBatteryState: UIDevice.BatteryState) -> BatteryStatus.State {
        switch uiDeviceBatteryState {
        case .unknown:      return .unknown
        case .unplugged:    return .unplugged
        case .charging:     return .charging
        case .full:         return .full
        @unknown default:   return.unknown
        }
    }
    #endif
}
