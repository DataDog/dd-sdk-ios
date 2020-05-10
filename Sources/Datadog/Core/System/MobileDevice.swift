/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

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

    convenience init(uiDevice: UIDevice, processInfo: ProcessInfo) {
        let wasBatteryMonitoringEnabled = uiDevice.isBatteryMonitoringEnabled
        self.init(
            model: uiDevice.model,
            osName: uiDevice.systemName,
            osVersion: uiDevice.systemVersion,
            enableBatteryStatusMonitoring: { uiDevice.isBatteryMonitoringEnabled = true },
            resetBatteryStatusMonitoring: { uiDevice.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled },
            currentBatteryStatus: {
                return BatteryStatus(
                    state: MobileDevice.toBatteryState(uiDevice.batteryState),
                    level: uiDevice.batteryLevel,
                    isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled
                )
            }
        )
    }

    /// Returns current mobile device  if `UIDevice` is available on this platform.
    /// On other platforms returns `nil`.
    static var current: MobileDevice {
        #if !targetEnvironment(simulator)
        // Real device
        return MobileDevice(uiDevice: UIDevice.current, processInfo: ProcessInfo.processInfo)
        #else
        // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        return MobileDevice(
            model: UIDevice.current.model,
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            enableBatteryStatusMonitoring: {},
            resetBatteryStatusMonitoring: {},
            currentBatteryStatus: { BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false) }
        )
        #endif
    }

    private static func toBatteryState(_ uiDeviceBatteryState: UIDevice.BatteryState) -> BatteryStatus.State {
        switch uiDeviceBatteryState {
        case .unknown:      return .unknown
        case .unplugged:    return .unplugged
        case .charging:     return .charging
        case .full:         return .full
        @unknown default:   return.unknown
        }
    }
}
