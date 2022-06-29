/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describes current device information.
internal struct DeviceInfo {
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

    init(
        name: String,
        model: String,
        osName: String,
        osVersion: String
    ) {
        self.name = name
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
    }
}

#if canImport(UIKit)

import UIKit

extension DeviceInfo {
    /// Creates device info based on UIKit description.
    ///
    /// - Parameters:
    ///   - model: The model name.
    ///   - device: The `UIDevice` description.
    init(
        model: String,
        device: UIDevice
    ) {
        self.init(
            name: device.model,
            model: model,
            osName: device.systemName,
            osVersion: device.systemVersion
        )
    }

    /// Creates device info based on UIKit description.
    ///
    /// - Parameters:
    ///   - processInfo: The current process information.
    ///   - device: The `UIDevice` description.
    init(
        processInfo: ProcessInfo = .processInfo,
        device: UIDevice = .current
    ) {
        #if !targetEnvironment(simulator)
        // Real iOS device
        self.init(
            name: device.model,
            model: (try? Sysctl.getModel()) ?? device.model,
            osName: device.systemName,
            osVersion: device.systemVersion
        )
        #else
        let model = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? device.model
        // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        self.init(
            name: device.model,
            model: "\(model) Simulator",
            osName: device.systemName,
            osVersion: device.systemVersion
        )
        #endif
    }
}
#endif
