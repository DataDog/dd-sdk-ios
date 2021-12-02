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
    let processInfo: ProcessInfo

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
        processInfo: ProcessInfo,
        enableBatteryStatusMonitoring: @escaping () -> Void,
        resetBatteryStatusMonitoring: @escaping () -> Void,
        currentBatteryStatus: @escaping () -> BatteryStatus
    ) {
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
        self.processInfo = processInfo
        self.enableBatteryStatusMonitoring = enableBatteryStatusMonitoring
        self.resetBatteryStatusMonitoring = resetBatteryStatusMonitoring
        self.currentBatteryStatus = currentBatteryStatus
    }

    convenience init(uiDevice: UIDevice, processInfo: ProcessInfo, notificationCenter: NotificationCenter) {
        let wasBatteryMonitoringEnabled = uiDevice.isBatteryMonitoringEnabled

        // We capture this `lowPowerModeMonitor` in `currentBatteryStatus` closure so its lifecycle
        // is owned and controlled by `MobileDevice` object.
        let lowPowerModeMonitor = LowPowerModeMonitor(initialProcessInfo: processInfo, notificationCenter: notificationCenter)

        self.init(
            model: uiDevice.model,
            osName: uiDevice.systemName,
            osVersion: uiDevice.systemVersion,
            processInfo: processInfo,
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

    // MARK: - Singleton
    private static var _instance: MobileDevice?

    /// Returns current mobile device  if `UIDevice` is available on this platform.
    /// On other platforms returns `nil`.
    static var current: MobileDevice {
        get {
            if let instance = _instance {
                return instance
            }

            #if !targetEnvironment(simulator)
            // Real device
            _instance = MobileDevice(
                uiDevice: UIDevice.current,
                processInfo: ProcessInfo.processInfo,
                notificationCenter: .default
            )
            #else
            // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
            _instance = MobileDevice(
                model: UIDevice.current.model,
                osName: UIDevice.current.systemName,
                osVersion: UIDevice.current.systemVersion,
                processInfo: ProcessInfo.processInfo,
                enableBatteryStatusMonitoring: {},
                resetBatteryStatusMonitoring: {},
                currentBatteryStatus: { BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false) }
            )
            #endif

            // swiftlint:disable:next force_unwrapping
            return _instance!
        }
        set(newInstance) {
            _instance = newInstance
        }
    }

    #if DD_SDK_COMPILED_FOR_TESTING
    static func clearForTesting() {
        _instance = nil
    }
    #endif

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
