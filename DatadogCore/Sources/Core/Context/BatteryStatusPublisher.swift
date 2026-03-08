/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS)
import UIKit

/// Produces `BatteryStatus` updates via `AsyncStream` by observing `UIDevice` battery
/// notifications.
///
/// Battery monitoring is enabled at creation time and restored to its original setting
/// when the stream terminates.
internal struct BatteryStatusSource: ContextValueSource {
    let initialValue: BatteryStatus?
    let values: AsyncStream<BatteryStatus?>

    init(
        notificationCenter: NotificationCenter,
        device: UIDevice
    ) {
        let wasBatteryMonitoringEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true

        self.initialValue = BatteryStatus(
            state: .init(device.batteryState),
            level: device.batteryLevel
        )

        self.values = AsyncStream { continuation in
            let block = { (notification: Notification) in
                guard let device = notification.object as? UIDevice else {
                    return
                }
                let status = BatteryStatus(
                    state: .init(device.batteryState),
                    level: device.batteryLevel
                )
                continuation.yield(status)
            }

            nonisolated(unsafe) let observers = [
                notificationCenter.addObserver(
                    forName: UIDevice.batteryStateDidChangeNotification,
                    object: device,
                    queue: .main,
                    using: block
                ),
                notificationCenter.addObserver(
                    forName: UIDevice.batteryLevelDidChangeNotification,
                    object: device,
                    queue: .main,
                    using: block
                )
            ]

            continuation.onTermination = { _ in
                observers.forEach(notificationCenter.removeObserver)
                device.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled
            }
        }
    }
}

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
