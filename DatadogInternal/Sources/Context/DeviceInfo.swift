/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current device information.
public struct DeviceInfo: Codable, Equatable, PassthroughAnyCodable {
    // MARK: - Info

    /// Device manufacturer name. Always'Apple'
    public let brand: String

    /// Device marketing name, e.g. "iPhone", "iPad", "iPod touch".
    public let name: String

    /// Device model name, e.g. "iPhone10,1", "iPhone13,2".
    public let model: String

    /// The name of operating system, e.g. "iOS", "iPadOS", "tvOS".
    public let osName: String

    /// The version of the operating system, e.g. "15.4.1".
    public let osVersion: String

    /// The build numer of the operating system, e.g.  "15D21" or "13D20".
    public let osBuildNumber: String?

    /// The architecture of the device
    public let architecture: String

    public init(
        name: String,
        model: String,
        osName: String,
        osVersion: String,
        osBuildNumber: String?,
        architecture: String
    ) {
        self.brand = "Apple"
        self.name = name
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
        self.osBuildNumber = osBuildNumber
        self.architecture = architecture
    }
}

#if canImport(UIKit)

import UIKit
import MachO

extension DeviceInfo {
    /// Creates device info based on UIKit description.
    ///
    /// - Parameters:
    ///   - processInfo: The current process information.
    ///   - device: The `UIDevice` description.
    public init(
        processInfo: ProcessInfo = .processInfo,
        device: UIDevice = .current
    ) {
        var architecture = "unknown"
        if let archInfo = NXGetLocalArchInfo()?.pointee {
            architecture = String(utf8String: archInfo.name) ?? "unknown"
        }

        let build = try? Sysctl.osVersion()

        #if !targetEnvironment(simulator)
        let model = try? Sysctl.model()
        // Real iOS device
        self.init(
            name: device.model,
            model: model ?? device.model,
            osName: device.systemName,
            osVersion: device.systemVersion,
            osBuildNumber: build,
            architecture: architecture
        )
        #else
        let model = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? device.model
        // iOS Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        self.init(
            name: device.model,
            model: "\(model) Simulator",
            osName: device.systemName,
            osVersion: device.systemVersion,
            osBuildNumber: build,
            architecture: architecture
        )
        #endif
    }
}
#endif
