/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS)
import UIKit

/// The ``BatteryStatusPublisher`` publishes the battery state and level from the ``UIDevice``.
///
/// The publisher will enable the battery monitoring by setting the ``UIDevice/isBatteryMonitoringEnabled``
/// to `true`. The property will be reset to it's initial value when the publisher is deallocated.
internal final class BatteryStatusPublisher: ContextValuePublisher {
    let initialValue: BatteryStatus?
    let device: UIDevice
    let isBatteryMonitoringEnabled: Bool
    private let notificationCenter: NotificationCenter
    private var observers: [Any]? = nil

    /// Creates a battery status publisher from the given device.
    /// 
    /// - Parameters:
    ///   - notificationCenter: The notification center for observing the `UIDevice` battery changes,
    ///   - device: The `UIDevice` instance. `.current` by default.
    init(
        notificationCenter: NotificationCenter,
        device: UIDevice = .current
    ) {
        self.device = device
        self.notificationCenter = notificationCenter
        self.isBatteryMonitoringEnabled = device.isBatteryMonitoringEnabled
        self.initialValue = BatteryStatus(
            state: .init(device.batteryState),
            level: device.batteryLevel
        )

        device.isBatteryMonitoringEnabled = true
    }

    func publish(to receiver: @escaping ContextValueReceiver<BatteryStatus?>) {
        let block = { (notification: Notification) in
            guard let device = notification.object as? UIDevice else {
                return
            }

            let status = BatteryStatus(
                state: .init(device.batteryState),
                level: device.batteryLevel
            )

            receiver(status)
        }

        observers = [
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
    }

    func cancel() {
        device.isBatteryMonitoringEnabled = isBatteryMonitoringEnabled
        observers?.forEach(notificationCenter.removeObserver)
        observers = nil
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
