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
    let isSavingEnergy: Bool
}

/// Shared provider to get current `BatteryStatus`.
internal protocol BatteryStatusProvider {
    var current: BatteryStatus { get }
}

#if canImport(UIKit) // SDK does not consider battery status when running on macOS
/// `BatteryStatusProvider` provider specific to platforms supporting `UIKit` (iOS 2.0+, Mac Catalyst 13.0+, ...).
internal struct UIKitBatteryStatusProvider: BatteryStatusProvider {
    var current: BatteryStatus {
        BatteryStatus(
            state: toBatteryState(UIDevice.current.batteryState),
            level: UIDevice.current.batteryLevel,
            isSavingEnergy: ProcessInfo.processInfo.isLowPowerModeEnabled
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
