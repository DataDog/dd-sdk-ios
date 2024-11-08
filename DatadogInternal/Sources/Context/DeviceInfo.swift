/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current device information.
public struct DeviceInfo: Codable, Equatable, PassthroughAnyCodable {
    /// Represents the type of device.
    public enum DeviceType: Codable, Equatable, PassthroughAnyCodable {
        case iPhone
        case iPod
        case iPad
        case appleTV
        case other(modelName: String, osName: String)
    }

    // MARK: - Info

    /// Device manufacturer name. Always'Apple'
    public let brand: String

    /// Device marketing name, e.g. "iPhone", "iPad", "iPod touch".
    public let name: String

    /// Device model name, e.g. "iPhone10,1", "iPhone13,2".
    public let model: String

    /// The type of device.
    public let type: DeviceType

    /// The name of operating system, e.g. "iOS", "iPadOS", "tvOS".
    public let osName: String

    /// The version of the operating system, e.g. "15.4.1".
    public let osVersion: String

    /// The build numer of the operating system, e.g.  "15D21" or "13D20".
    public let osBuildNumber: String?

    /// The architecture of the device
    public let architecture: String

    /// The device is a simulator
    public let isSimulator: Bool

    /// The vendor identifier of the device.
    public let vendorId: String?

    /// Returns `true` if the debugger is attached.
    public let isDebugging: Bool

    /// Returns system boot time since epoch.
    public let systemBootTime: TimeInterval

    public init(
        name: String,
        model: String,
        osName: String,
        osVersion: String,
        osBuildNumber: String?,
        architecture: String,
        isSimulator: Bool,
        vendorId: String?,
        isDebugging: Bool,
        systemBootTime: TimeInterval
    ) {
        self.brand = "Apple"
        self.name = name
        self.model = model
        self.type = DeviceType(modelName: model, osName: osName)
        self.osName = osName
        self.osVersion = osVersion
        self.osBuildNumber = osBuildNumber
        self.architecture = architecture
        self.isSimulator = isSimulator
        self.vendorId = vendorId
        self.isDebugging = isDebugging
        self.systemBootTime = systemBootTime
    }
}

private extension DeviceInfo.DeviceType {
    /// Infers `DeviceType` from provided model name and operating system name.
    /// - Parameters:
    ///   - modelName: The name of the device model, e.g. "iPhone10,1".
    ///   - osName: The name of the operating system, e.g. "iOS", "tvOS".
    init(modelName: String, osName: String) {
        let lowercasedModelName = modelName.lowercased()
        let lowercasedOSName = osName.lowercased()

        if lowercasedModelName.hasPrefix("iphone") {
            self = .iPhone
        } else if lowercasedModelName.hasPrefix("ipod") {
            self = .iPod
        } else if lowercasedModelName.hasPrefix("ipad") {
            self = .iPad
        } else if lowercasedModelName.hasPrefix("appletv") || lowercasedOSName == "tvos" {
            self = .appleTV
        } else {
            self = .other(modelName: modelName, osName: osName)
        }
    }
}

import MachO

#if canImport(UIKit)
import UIKit

extension DeviceInfo {
    /// Creates device info based on device description.
    ///
    /// - Parameters:
    ///   - processInfo: The current process information.
    ///   - device: The device description.
    public init(
        processInfo: ProcessInfo,
        device: _UIDevice = .dd.current,
        sysctl: SysctlProviding = Sysctl()
    ) {
        var architecture = "unknown"
        if let archInfo = NXGetLocalArchInfo()?.pointee {
            architecture = String(utf8String: archInfo.name) ?? "unknown"
        }

        let build = try? sysctl.osBuild()
        let isDebugging = try? sysctl.isDebugging()
        let systemBootTime = try? sysctl.systemBootTime()

        #if !targetEnvironment(simulator)
        let model = try? sysctl.model()
        // Real device
        self.init(
            name: device.model,
            model: model ?? device.model,
            osName: device.systemName,
            osVersion: device.systemVersion,
            osBuildNumber: build,
            architecture: architecture,
            isSimulator: false,
            vendorId: device.identifierForVendor?.uuidString,
            isDebugging: isDebugging ?? false,
            systemBootTime: systemBootTime ?? Date.timeIntervalSinceReferenceDate
        )
        #else
        let model = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? device.model
        // Simulator - battery monitoring doesn't work on Simulator, so return "always OK" value
        self.init(
            name: device.model,
            model: "\(model) Simulator",
            osName: device.systemName,
            osVersion: device.systemVersion,
            osBuildNumber: build,
            architecture: architecture,
            isSimulator: true,
            vendorId: device.identifierForVendor?.uuidString,
            isDebugging: isDebugging ?? false,
            systemBootTime: systemBootTime ?? Date.timeIntervalSinceReferenceDate
        )
        #endif
    }
}
#elseif os(macOS)
/// Creates device info based on Host description.
///
/// - Parameters:
///   - processInfo: The current process information.
extension DeviceInfo {
    public init(
        processInfo: ProcessInfo = .processInfo,
        sysctl: SysctlProviding = Sysctl()
    ) {
        var architecture = "unknown"
        if let archInfo = NXGetLocalArchInfo()?.pointee {
            architecture = String(utf8String: archInfo.name) ?? "unknown"
        }

        let build = (try? sysctl.osBuild()) ?? ""
        let model = (try? sysctl.model()) ?? ""
        let systemVersion = processInfo.operatingSystemVersion
        let systemBootTime = try? sysctl.systemBootTime()
        let isDebugging = try? sysctl.isDebugging()
#if targetEnvironment(simulator)
        let isSimulator = true
#else
        let isSimulator = false
#endif

        self.init(
            name: model.components(separatedBy: CharacterSet.letters.inverted).joined(),
            model: model,
            osName: "macOS",
            osVersion: "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)",
            osBuildNumber: build,
            architecture: architecture,
            isSimulator: isSimulator,
            vendorId: nil,
            isDebugging: isDebugging ?? false,
            systemBootTime: systemBootTime ?? Date.timeIntervalSinceReferenceDate
        )
    }
}
#endif

#if canImport(WatchKit)
import WatchKit

public typealias _UIDevice = WKInterfaceDevice

extension _UIDevice: DatadogExtended {}
extension DatadogExtension where ExtendedType == _UIDevice {
    /// Returns the shared device object.
    public static var current: ExtendedType { .current() }
}
#elseif canImport(UIKit)
import UIKit

public typealias _UIDevice = UIDevice

extension _UIDevice: DatadogExtended {}
extension DatadogExtension where ExtendedType == _UIDevice {
    /// Returns the shared device object.
    public static var current: ExtendedType { .current }
}
#endif
