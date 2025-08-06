/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current device information.
public struct DeviceInfo: Equatable {
    /// Device manufacturer name. Always'Apple'
    public let brand: String

    /// Device marketing name, e.g. "iPhone", "iPad", "iPod touch".
    public let name: String

    /// Device model name, e.g. "iPhone10,1", "iPhone13,2".
    public let model: String

    /// The type of device.
    public let type: DeviceType

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
        architecture: String,
        isSimulator: Bool,
        vendorId: String?,
        isDebugging: Bool,
        systemBootTime: TimeInterval
    ) {
        self.brand = "Apple"
        self.name = name
        self.model = model
        self.type = .init(modelName: model, osName: osName)
        self.architecture = architecture
        self.isSimulator = isSimulator
        self.vendorId = vendorId
        self.isDebugging = isDebugging
        self.systemBootTime = systemBootTime
    }
}

extension DeviceInfo {
    /// Represents the type of device.
    public enum DeviceType: Codable, Equatable {
        case iPhone
        case iPod
        case iPad
        case appleTV
        case appleVision
        case appleWatch
        case other(model: String, os: String)

        public var normalizedDeviceType: Device.DeviceType {
            switch self {
            case .iPhone, .iPod:
                    .mobile
            case .iPad:
                    .tablet
            case .appleTV:
                    .tv
            case .appleVision, .appleWatch, .other:
                    .other
            }
        }
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
        } else if lowercasedModelName.hasPrefix("ipad") || (lowercasedOSName == "ipados" && lowercasedModelName.hasPrefix("realitydevice") == false) {
            self = .iPad
        } else if lowercasedModelName.hasPrefix("appletv") || lowercasedOSName == "tvos" || lowercasedOSName == "apple tvos" {
            self = .appleTV
        } else if lowercasedModelName.hasPrefix("realitydevice") || lowercasedOSName == "visionos" {
            self = .appleVision
        } else if lowercasedModelName.hasPrefix("watch") || lowercasedOSName == "watchos" {
            self = .appleWatch
        } else {
            self = .other(model: modelName, os: osName)
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

        let isDebugging = try? sysctl.isDebugging()
        let systemBootTime = try? sysctl.systemBootTime()

        #if !targetEnvironment(simulator)
        let model = try? sysctl.model()
        // Real device
        self.init(
            name: device.model,
            model: model ?? device.model,
            osName: device.systemName,
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

        let model = (try? sysctl.model()) ?? ""
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

extension DatadogContext {
    /// Current device information to send in the events.
    public var normalizedDevice: Device {
        .init(
            architecture: device.architecture,
            batteryLevel: Double(batteryStatus?.level ?? 0),
            brand: device.brand,
            brightnessLevel: Double(brightnessLevel ?? 0),
            locale: localeInfo.currentLocale,
            locales: localeInfo.locales,
            model: device.model,
            name: device.name,
            powerSavingMode: isLowPowerModeEnabled,
            timeZone: localeInfo.timeZoneIdentifier,
            type: device.type.normalizedDeviceType
        )
    }
}
