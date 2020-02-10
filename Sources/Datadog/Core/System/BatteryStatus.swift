import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Describes battery conditions.
internal struct BatteryStatus {
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

/// Shared provider to get current `BatteryStatus`.
internal protocol BatteryStatusProviderType {
    var current: BatteryStatus { get }
}

#if canImport(UIKit) // SDK does not consider battery status when running on macOS
/// `BatteryStatusProvider` provider specific to platforms supporting `UIKit` (iOS 2.0+, Mac Catalyst 13.0+, ...).
internal class BatteryStatusProvider: BatteryStatusProviderType {
    private var originalIsBatteryMonitoringEnabled: Bool

    init() {
        originalIsBatteryMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    deinit {
        UIDevice.current.isBatteryMonitoringEnabled = originalIsBatteryMonitoringEnabled
    }

    var current: BatteryStatus {
        BatteryStatus(
            state: toBatteryState(UIDevice.current.batteryState),
            level: UIDevice.current.batteryLevel,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private func toBatteryState(_ uiDeviceBatteryState: UIDevice.BatteryState) -> BatteryStatus.State {
        switch uiDeviceBatteryState {
        case .unknown:      return .unknown
        case .unplugged:    return .unplugged
        case .charging:     return .charging
        case .full:         return .full
        @unknown default:   return.unknown
        }
    }
}
#endif
