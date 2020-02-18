/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Convenience typealias.
internal typealias BatteryStatus = MobileDevice.BatteryStatus

/// Shared provider to get current `BatteryStatus`.
internal protocol BatteryStatusProviderType {
    var current: BatteryStatus { get }
}

internal class BatteryStatusProvider: BatteryStatusProviderType {
    private let mobileDevice: MobileDevice

    /// `BatteryStatusProvider` can be only instantiated for mobile devices.
    /// SDK does not consider battery status when running on other platforms.
    init(mobileDevice: MobileDevice) {
        self.mobileDevice = mobileDevice
        mobileDevice.enableBatteryStatusMonitoring()
    }

    deinit {
        mobileDevice.resetBatteryStatusMonitoring()
    }

    var current: BatteryStatus { mobileDevice.currentBatteryStatus() }
}
