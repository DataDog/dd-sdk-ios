/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogLogs
import DatadogInternal

@objc
public class DDLogEvent: NSObject {
    internal var swiftModel: LogEvent

    internal init(swiftModel: LogEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var date: Date {
        swiftModel.date
    }

    @objc public var status: DDLogEventStatus {
        .init(swift: swiftModel.status)
    }

    @objc public var message: String {
        set { swiftModel.message = newValue }
        get { swiftModel.message }
    }

    @objc public var error: DDLogEventError? {
        if swiftModel.error != nil {
            .init(root: self)
        } else {
            nil
        }
    }

    @objc public var serviceName: String {
        swiftModel.serviceName
    }

    @objc public var environment: String {
        swiftModel.environment
    }

    @objc public var loggerName: String {
        swiftModel.loggerName
    }

    @objc public var loggerVersion: String {
        swiftModel.loggerVersion
    }

    @objc public var threadName: String? {
        swiftModel.threadName
    }

    @objc public var applicationVersion: String {
        swiftModel.applicationVersion
    }

    @objc public var applicationBuildNumber: String {
        swiftModel.applicationBuildNumber
    }

    @objc public var buildId: String? {
        swiftModel.buildId
    }

    @objc public var variant: String? {
        swiftModel.variant
    }

    @objc public var dd: DDLogEventDd {
        .init(root: self)
    }

    @objc public var os: DDLogEventOperatingSystem {
        .init(root: self)
    }

    @objc public var userInfo: DDLogEventUserInfo {
        .init(root: self)
    }

    @objc public var accountInfo: DDLogEventAccountInfo {
        .init(root: self)
    }

    @objc public var networkConnectionInfo: DDLogEventNetworkConnectionInfo? {
        if swiftModel.networkConnectionInfo != nil {
            .init(root: self)
        } else {
            nil
        }
    }

    @objc public var mobileCarrierInfo: DDLogEventCarrierInfo? {
        if swiftModel.mobileCarrierInfo != nil {
            .init(root: self)
        } else {
            nil
        }
    }

    @objc public var attributes: DDLogEventAttributes {
        .init(root: self)
    }

    @objc public var tags: [String]? {
        set { swiftModel.tags = newValue }
        get { swiftModel.tags }
    }
}

@objc
public enum DDLogEventStatus: Int {
    internal init(swift: LogEvent.Status) {
        switch swift {
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warn: self = .warn
        case .error: self = .error
        case .critical: self = .critical
        case .emergency: self = .emergency
        }
    }

    internal var toSwift: LogEvent.Status {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warn: return .warn
        case .error: return .error
        case .critical: return .critical
        case .emergency: return .emergency
        }
    }

    case debug
    case info
    case notice
    case warn
    case error
    case critical
    case emergency
}

@objc
public class DDLogEventAttributes: NSObject {
    internal var root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var userAttributes: [String: Any] {
        set { root.swiftModel.attributes.userAttributes = newValue.dd.swiftAttributes }
        get { root.swiftModel.attributes.userAttributes.dd.objCAttributes }
    }
}

@objc
public class DDLogEventUserInfo: NSObject {
    internal var root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var id: String? {
        root.swiftModel.userInfo.id
    }

    @objc public var name: String? {
        root.swiftModel.userInfo.name
    }

    @objc public var email: String? {
        root.swiftModel.userInfo.email
    }

    @objc public var extraInfo: [String: Any] {
        set { root.swiftModel.userInfo.extraInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.userInfo.extraInfo.dd.objCAttributes }
    }
}

@objc
public class DDLogEventAccountInfo: NSObject {
    internal let root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    // swiftlint:disable force_unwrapping
    @objc public var id: String {
        root.swiftModel.accountInfo!.id
    }

    @objc public var name: String? {
        root.swiftModel.accountInfo!.name
    }

    @objc public var extraInfo: [String: Any] {
        set { root.swiftModel.accountInfo!.extraInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.accountInfo!.extraInfo.dd.objCAttributes }
    }
    // swiftlint:enable force_unwrapping
}

@objc
public class DDLogEventError: NSObject {
    internal var root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var kind: String? {
        set { root.swiftModel.error?.kind = newValue }
        get { root.swiftModel.error?.kind }
    }

    @objc public var message: String? {
        set { root.swiftModel.error?.message = newValue }
        get { root.swiftModel.error?.message }
    }

    @objc public var stack: String? {
        set { root.swiftModel.error?.stack = newValue }
        get { root.swiftModel.error?.stack }
    }

    @objc public var sourceType: String {
        // swiftlint:disable force_unwrapping
        set { root.swiftModel.error!.sourceType = newValue }
        get { root.swiftModel.error!.sourceType }
        // swiftlint:enable force_unwrapping
    }

    @objc public var fingerprint: String? {
        set { root.swiftModel.error?.fingerprint = newValue }
        get { root.swiftModel.error?.fingerprint }
    }

    @objc public var binaryImages: [DDLogEventBinaryImage]? {
        set { root.swiftModel.error?.binaryImages = newValue?.map { $0.swiftModel } }
        get { root.swiftModel.error?.binaryImages?.map { DDLogEventBinaryImage(swiftModel: $0) } }
    }
}

@objc
public class DDLogEventBinaryImage: NSObject {
    internal let swiftModel: LogEvent.Error.BinaryImage

    internal init(swiftModel: LogEvent.Error.BinaryImage) {
        self.swiftModel = swiftModel
    }

    @objc public var arch: String? {
        swiftModel.arch
    }

    @objc public var isSystem: Bool {
        swiftModel.isSystem
    }

    @objc public var loadAddress: String? {
        swiftModel.loadAddress
    }

    @objc public var maxAddress: String? {
        swiftModel.maxAddress
    }

    @objc public var name: String {
        swiftModel.name
    }

    @objc public var uuid: String {
        swiftModel.uuid
    }
}

@objc
public class DDLogEventOperatingSystem: NSObject {
    internal let root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var name: String {
        root.swiftModel.os.name
    }

    @objc public var version: String {
        root.swiftModel.os.version
    }

    @objc public var build: String? {
        root.swiftModel.os.build
    }
}

@objc
public class DDLogEventDd: NSObject {
    internal let root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var device: DDLogEventDeviceInfo {
        .init(root: root)
    }
}

@objc
public class DDLogEventDeviceInfo: NSObject {
    internal let root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var brand: String {
        root.swiftModel.dd.device.brand
    }

    @objc public var name: String {
        root.swiftModel.dd.device.name
    }

    @objc public var model: String {
        root.swiftModel.dd.device.model
    }

    @objc public var architecture: String {
        root.swiftModel.dd.device.architecture
    }
}

@objc
public class DDLogEventNetworkConnectionInfo: NSObject {
    internal let root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var reachability: DDLogEventReachability {
        // swiftlint:disable force_unwrapping
        .init(swift: root.swiftModel.networkConnectionInfo!.reachability)
        // swiftlint:enable force_unwrapping
    }

    @objc public var availableInterfaces: [Int]? {
        root.swiftModel.networkConnectionInfo?.availableInterfaces?.map { DDLogEventInterface(swift: $0).rawValue }
    }

    @objc public var supportsIPv4: NSNumber? {
        root.swiftModel.networkConnectionInfo?.supportsIPv4 as NSNumber?
    }

    @objc public var supportsIPv6: NSNumber? {
        root.swiftModel.networkConnectionInfo?.supportsIPv6 as NSNumber?
    }

    @objc public var isExpensive: NSNumber? {
        root.swiftModel.networkConnectionInfo?.isExpensive as NSNumber?
    }

    @objc public var isConstrained: NSNumber? {
        root.swiftModel.networkConnectionInfo?.isConstrained as NSNumber?
    }
}

@objc
public enum DDLogEventReachability: Int {
    internal init(swift: NetworkConnectionInfo.Reachability) {
        switch swift {
        case .yes: self = .yes
        case .maybe: self = .maybe
        case .no: self = .no
        }
    }

    internal var toSwift: NetworkConnectionInfo.Reachability {
        switch self {
        case .yes: return .yes
        case .maybe: return .maybe
        case .no: return .no
        }
    }

    case yes
    case maybe
    case no
}

@objc
public enum DDLogEventInterface: Int {
    internal init(swift: NetworkConnectionInfo.Interface) {
        switch swift {
        case .wifi: self = .wifi
        case .wiredEthernet: self = .wiredEthernet
        case .cellular: self = .cellular
        case .loopback: self = .loopback
        case .other: self = .other
        }
    }

    internal var toSwift: NetworkConnectionInfo.Interface {
        switch self {
        case .wifi: return .wifi
        case .wiredEthernet: return .wiredEthernet
        case .cellular: return .cellular
        case .loopback: return .loopback
        case .other: return .other
        }
    }

    case wifi
    case wiredEthernet
    case cellular
    case loopback
    case other
}

@objc
public class DDLogEventCarrierInfo: NSObject {
    internal let root: DDLogEvent

    internal init(root: DDLogEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.mobileCarrierInfo?.carrierName
    }

    @objc public var carrierISOCountryCode: String? {
        root.swiftModel.mobileCarrierInfo?.carrierISOCountryCode
    }

    @objc public var carrierAllowsVOIP: Bool {
        // swiftlint:disable force_unwrapping
        root.swiftModel.mobileCarrierInfo!.carrierAllowsVOIP
        // swiftlint:enable force_unwrapping
    }

    @objc public var radioAccessTechnology: DDLogEventRadioAccessTechnology {
        // swiftlint:disable force_unwrapping
        .init(swift: root.swiftModel.mobileCarrierInfo!.radioAccessTechnology)
        // swiftlint:enable force_unwrapping
    }
}

@objc
public enum DDLogEventRadioAccessTechnology: Int {
    internal init(swift: CarrierInfo.RadioAccessTechnology) {
        switch swift {
        case .GPRS: self = .GPRS
        case .Edge: self = .Edge
        case .WCDMA: self = .WCDMA
        case .HSDPA: self = .HSDPA
        case .HSUPA: self = .HSUPA
        case .CDMA1x: self = .CDMA1x
        case .CDMAEVDORev0: self = .CDMAEVDORev0
        case .CDMAEVDORevA: self = .CDMAEVDORevA
        case .CDMAEVDORevB: self = .CDMAEVDORevB
        case .eHRPD: self = .eHRPD
        case .LTE: self = .LTE
        case .unknown: self = .unknown
        }
    }

    internal var toSwift: CarrierInfo.RadioAccessTechnology {
        switch self {
        case .GPRS: return .GPRS
        case .Edge: return .Edge
        case .WCDMA: return .WCDMA
        case .HSDPA: return .HSDPA
        case .HSUPA: return .HSUPA
        case .CDMA1x: return .CDMA1x
        case .CDMAEVDORev0: return .CDMAEVDORev0
        case .CDMAEVDORevA: return .CDMAEVDORevA
        case .CDMAEVDORevB: return .CDMAEVDORevB
        case .eHRPD: return .eHRPD
        case .LTE: return .LTE
        case .unknown: return .unknown
        }
    }

    case GPRS
    case Edge
    case WCDMA
    case HSDPA
    case HSUPA
    case CDMA1x
    case CDMAEVDORev0
    case CDMAEVDORevA
    case CDMAEVDORevB
    case eHRPD
    case LTE
    case unknown
}
