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

    #if os(iOS)
    convenience init(uiDevice: UIDevice, processInfo: ProcessInfo, notificationCenter: NotificationCenter) {
        let wasBatteryMonitoringEnabled = uiDevice.isBatteryMonitoringEnabled

        // We capture this `lowPowerModeMonitor` in `currentBatteryStatus` closure so its lifecycle
        // is owned and controlled by `MobileDevice` object.
        let lowPowerModeMonitor = LowPowerModeMonitor(initialProcessInfo: processInfo, notificationCenter: notificationCenter)

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
                    isLowPowerModeEnabled: lowPowerModeMonitor.isLowPowerModeEnabled
                )
            }
        )
    }

    convenience init() {
        #if !targetEnvironment(simulator)
        // Real device
        self.init(
            uiDevice: UIDevice.current,
            processInfo: ProcessInfo.processInfo,
            notificationCenter: .default
        )
        #else
        // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        self.init(
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

    #else
    convenience init(
        uiDevice: UIDevice = .current,
        processInfo: ProcessInfo = .processInfo,
        notificationCenter: NotificationCenter = .default
    ) {
        // iOS Simulator - battery monitoring doesn't work on tvOS nor Simulator, so return "always OK" value
        self.init(
            model: uiDevice.model,
            osName: uiDevice.systemName,
            osVersion: uiDevice.systemVersion,
            enableBatteryStatusMonitoring: {},
            resetBatteryStatusMonitoring: {},
            currentBatteryStatus: { BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false) }
        )
    }
    #endif
}

/// Observes "Low Power Mode" setting changes and provides `isLowPowerModeEnabled` value in a thread-safe manner.
///
/// Note: this was added in https://github.com/DataDog/dd-sdk-ios/issues/609 where `ProcessInfo.isLowPowerModeEnabled` was considered
/// not thread-safe on iOS 15. We suspect a bug present in iOS 15, where accessing `processInfo.isLowPowerModeEnabled` within a pending
/// `.NSProcessInfoPowerStateDidChange` completion handler can sometimes lead to `_os_unfair_lock_recursive_abort` crash. The issue
/// was reported to Apple, ref.: https://openradar.appspot.com/FB9741207
private final class LowPowerModeMonitor {
    var isLowPowerModeEnabled: Bool {
        publisher.currentValue
    }

    private let publisher: ValuePublisher<Bool>
    private let notificationCenter: NotificationCenter
    private var powerStateDidChangeObserver: Any?

    init(initialProcessInfo: ProcessInfo, notificationCenter: NotificationCenter) {
        self.publisher = ValuePublisher(initialValue: initialProcessInfo.isLowPowerModeEnabled)
        self.notificationCenter = notificationCenter
        self.powerStateDidChangeObserver = notificationCenter
            .addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let processInfo = notification.object as? ProcessInfo else {
                    return
                }

                // We suspect an iOS 15 bug (ref.: https://openradar.appspot.com/FB9741207) which leads to rare
                // `_os_unfair_lock_recursive_abort` crash when `processInfo.isLowPowerModeEnabled` is accessed
                // directly in the notification handler. As a workaround, we defer its access to the next run loop
                // where underlying lock should be already released.
                OperationQueue.main.addOperation {
                    let nextValue = processInfo.isLowPowerModeEnabled
                    self?.publisher.publishAsync(nextValue)
                }
            }
    }

    deinit {
        if let observer = powerStateDidChangeObserver {
            notificationCenter.removeObserver(observer)
        }
    }
}
