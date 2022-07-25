/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if os(iOS)

import UIKit

internal final class BatteryStatusReader: ContextValueReader {
    let initialValue: BatteryStatus?

    let device: UIDevice
    let isBatteryMonitoringEnabled: Bool

    init(device: UIDevice = .current) {
        self.device = device
        self.isBatteryMonitoringEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true

        self.initialValue = BatteryStatus(
            state: .init(device.batteryState),
            level: device.batteryLevel
        )
    }

    func read(to receiver: inout BatteryStatus?) {
        receiver = BatteryStatus(
            state: .init(device.batteryState),
            level: device.batteryLevel
        )
    }

    deinit {
        device.isBatteryMonitoringEnabled = isBatteryMonitoringEnabled
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
