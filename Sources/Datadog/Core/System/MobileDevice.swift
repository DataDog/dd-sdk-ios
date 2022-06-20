/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// Describes current mobile device.
internal class MobileDevice {
    // MARK: - Info

    /// Device manufacturer name.
    let brand = "Apple"

    /// Device marketing name, e.g. "iPhone", "iPad", "iPod touch".
    let name: String

    /// Device model name, e.g. "iPhone10,1", "iPhone13,2".
    let model: String

    /// The name of operating system, e.g. "iOS", "iPadOS", "tvOS".
    let osName: String

    /// The version of the operating system, e.g. "15.4.1".
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
        name: String,
        model: String,
        osName: String,
        osVersion: String,
        enableBatteryStatusMonitoring: @escaping () -> Void,
        resetBatteryStatusMonitoring: @escaping () -> Void,
        currentBatteryStatus: @escaping () -> BatteryStatus
    ) {
        self.name = name
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
        self.enableBatteryStatusMonitoring = enableBatteryStatusMonitoring
        self.resetBatteryStatusMonitoring = resetBatteryStatusMonitoring
        self.currentBatteryStatus = currentBatteryStatus
    }

    #if os(iOS)

    convenience init(
        model: String,
        uiDevice: UIDevice,
        processInfo: ProcessInfo,
        notificationCenter: NotificationCenter
    ) {
        let wasBatteryMonitoringEnabled = uiDevice.isBatteryMonitoringEnabled

        // We capture this `lowPowerModeMonitor` in `currentBatteryStatus` closure so its lifecycle
        // is owned and controlled by `MobileDevice` object.
        let lowPowerModeMonitor = LowPowerModeMonitor(initialProcessInfo: processInfo, notificationCenter: notificationCenter)

        self.init(
            name: uiDevice.model,
            model: model,
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
        let processInfo = ProcessInfo.processInfo
        let device = UIDevice.current

        #if !targetEnvironment(simulator)
        // Real iOS device
        self.init(
            model: (try? Sysctl.getModel()) ?? device.model,
            uiDevice: device,
            processInfo: processInfo,
            notificationCenter: .default
        )
        #else
        let model = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? device.model
        // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        self.init(
            name: device.model,
            model: "\(model) Simulator",
            osName: device.systemName,
            osVersion: device.systemVersion,
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

    #elseif os(tvOS)

    convenience init(
        model: String,
        uiDevice: UIDevice,
        processInfo: ProcessInfo,
        notificationCenter: NotificationCenter
    ) {
        self.init(
            name: uiDevice.model,
            model: model,
            osName: uiDevice.systemName,
            osVersion: uiDevice.systemVersion,
            // Battery monitoring doesn't work on tvOS, so return "always OK" value:
            enableBatteryStatusMonitoring: {},
            resetBatteryStatusMonitoring: {},
            currentBatteryStatus: { BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false) }
        )
    }

    convenience init() {
        let processInfo = ProcessInfo.processInfo
        let device = UIDevice.current
        let model: String

        #if !targetEnvironment(simulator)
        // Real tvOS device
        model = (try? Sysctl.getModel()) ?? device.model
        #else
        // tvOS Simulator
        let simulatorModel = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? device.model
        model = "\(simulatorModel) Simulator"
        #endif

        self.init(
            model: model,
            uiDevice: device,
            processInfo: processInfo,
            notificationCenter: .default
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
