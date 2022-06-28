/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describe the battery state for mobile devices.
internal struct BatteryStatus {
    enum State: Equatable {
        case unknown
        case unplugged
        case charging
        case full
    }

    /// The charging state of the battery.
    let state: State

    /// The battery power level, range between 0 and 1.
    let level: Float

    /// `true` if the Low Power Mode is enabled.
    let isLowPowerModeEnabled: Bool
}

/// Shared provider to get current `BatteryStatus`.
internal protocol BatteryStatusProviderType {
    /// The current status of the battery.
    var current: BatteryStatus { get }
}

internal class BatteryStatusProvider: BatteryStatusProviderType {
    /// Resets battery status monitoring.
    private let resetBatteryStatusMonitoring: () -> Void
    /// Returns current `BatteryStatus`.
    private let currentBatteryStatus: () -> BatteryStatus
    /// The current status of the battery.
    var current: BatteryStatus { currentBatteryStatus() }

    /// Creates a battery status provider to monitor the battery.
    ///
    /// - Parameters:
    ///   - enableBatteryStatusMonitoring: closure to enable monitoring.
    ///   - resetBatteryStatusMonitoring: closure to reset monitoring.
    ///   - currentBatteryStatus: closure to get the current battery status.
    init(
        enableBatteryStatusMonitoring: () -> Void,
        resetBatteryStatusMonitoring: @escaping () -> Void,
        currentBatteryStatus: @escaping () -> BatteryStatus
    ) {
        self.resetBatteryStatusMonitoring = resetBatteryStatusMonitoring
        self.currentBatteryStatus = currentBatteryStatus
        enableBatteryStatusMonitoring()
    }

    deinit {
        resetBatteryStatusMonitoring()
    }
}

/// Observes "Low Power Mode" setting changes and provides `isLowPowerModeEnabled` value in a thread-safe manner.
///
/// Note: this was added in https://github.com/DataDog/dd-sdk-ios/issues/609 where `ProcessInfo.isLowPowerModeEnabled` was considered
/// not thread-safe on iOS 15. We suspect a bug present in iOS 15, where accessing `processInfo.isLowPowerModeEnabled` within a pending
/// `.NSProcessInfoPowerStateDidChange` completion handler can sometimes lead to `_os_unfair_lock_recursive_abort` crash. The issue
/// was reported to Apple, ref.: https://openradar.appspot.com/FB9741207
private final class LowPowerModeMonitor {
    /// `true` if the Low Power Mode is enabled.
    var isLowPowerModeEnabled: Bool {
        publisher.currentValue
    }

    private let publisher: ValuePublisher<Bool>
    private let notificationCenter: NotificationCenter
    private var powerStateDidChangeObserver: Any?

    /// Creates a monitor.
    ///
    /// The monitor will strat observing the `NSNotification.Name.NSProcessInfoPowerStateDidChange` at
    /// initialization. Deallocating the monitor will remove the notification observer.
    ///
    /// - Parameters:
    ///   - initialState: The initiale low power mode state.
    ///   - notificationCenter: The notification center where to observe the Low Power Mode notification.
    init(initialState: Bool, notificationCenter: NotificationCenter) {
        self.publisher = ValuePublisher(initialValue: initialState)
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

#if canImport(UIKit)
import UIKit

extension BatteryStatusProvider {
    /// Initialize a default Battery Status Provider.
    ///
    /// This initializer take the target plaform in consideration.
    convenience init() {
        #if targetEnvironment(simulator) || os(tvOS)
        // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        self.init(
            enableBatteryStatusMonitoring: {},
            resetBatteryStatusMonitoring: {},
            currentBatteryStatus: { BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false) }
        )
        #elseif os(iOS)
        self.init(
            device: .current,
            processInfo: .processInfo,
            notificationCenter: .default
        )
        #endif
    }

    #if os(iOS)
    /// Create a Battery Status Provider for iOS devices only.
    ///
    /// - Parameters:
    ///   - device: The `UIDevice` description.
    ///   - processInfo: The process info.
    ///   - notificationCenter: The notification center where to observe the Low Power Mode notification.
    convenience init(
        device: UIDevice,
        processInfo: ProcessInfo,
        notificationCenter: NotificationCenter
    ) {
        // Real iOS device
        let wasBatteryMonitoringEnabled = device.isBatteryMonitoringEnabled
        // We capture this `lowPowerModeMonitor` in `currentBatteryStatus` closure so its lifecycle
        // is owned and controlled by `MobileDevice` object.
        let lowPowerModeMonitor = LowPowerModeMonitor(
            initialState: processInfo.isLowPowerModeEnabled,
            notificationCenter: notificationCenter
        )

        self.init(
            enableBatteryStatusMonitoring: { device.isBatteryMonitoringEnabled = true },
            resetBatteryStatusMonitoring: { device.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled },
            currentBatteryStatus: {
                return BatteryStatus(
                    state: .init(device.batteryState),
                    level: device.batteryLevel,
                    isLowPowerModeEnabled: lowPowerModeMonitor.isLowPowerModeEnabled
                )
            }
        )
    }
    #endif
}

#if !os(tvOS)
extension BatteryStatus.State {
    /// Cast `UIDevice.BatteryState` to `BatteryStatus.State`
    /// 
    /// - Parameter state: The state to cast.
    init(_ state: UIDevice.BatteryState) {
        switch state {
        case .unknown:
            self = .unknown
        case .unplugged:
            self = .unplugged
        case .charging:
            self = .charging
        case .full:
            self = .full
        @unknown default:
            self = .unknown
        }
    }
}
#endif

#endif
