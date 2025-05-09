/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@objc(DDLogEvent)
@objcMembers
@_spi(objc)
public class objc_LogEvent: NSObject {
    internal var swiftModel: LogEvent

    internal init(swiftModel: LogEvent) {
        self.swiftModel = swiftModel
    }

    public var date: Date {
        swiftModel.date
    }

    public var status: objc_LogEventStatus {
        .init(swift: swiftModel.status)
    }

    public var message: String {
        set { swiftModel.message = newValue }
        get { swiftModel.message }
    }

    public var error: objc_LogEventError? {
        if swiftModel.error != nil {
            .init(root: self)
        } else {
            nil
        }
    }

    public var serviceName: String {
        swiftModel.serviceName
    }

    public var environment: String {
        swiftModel.environment
    }

    public var loggerName: String {
        swiftModel.loggerName
    }

    public var loggerVersion: String {
        swiftModel.loggerVersion
    }

    public var threadName: String? {
        swiftModel.threadName
    }

    public var applicationVersion: String {
        swiftModel.applicationVersion
    }

    public var applicationBuildNumber: String {
        swiftModel.applicationBuildNumber
    }

    public var buildId: String? {
        swiftModel.buildId
    }

    public var variant: String? {
        swiftModel.variant
    }

    public var dd: objc_LogEventDd {
        .init(root: self)
    }

    public var os: objc_LogEventOperatingSystem {
        .init(root: self)
    }

    public var userInfo: objc_LogEventUserInfo {
        .init(root: self)
    }

    public var networkConnectionInfo: objc_LogEventNetworkConnectionInfo? {
        if swiftModel.networkConnectionInfo != nil {
            .init(root: self)
        } else {
            nil
        }
    }

    public var mobileCarrierInfo: objc_LogEventCarrierInfo? {
        if swiftModel.mobileCarrierInfo != nil {
            .init(root: self)
        } else {
            nil
        }
    }

    public var attributes: objc_LogEventAttributes {
        .init(root: self)
    }

    public var tags: [String]? {
        set { swiftModel.tags = newValue }
        get { swiftModel.tags }
    }
}

@objc(DDLogEventStatus)
@_spi(objc)
public enum objc_LogEventStatus: Int {
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

@objc(DDLogEventAttributes)
@objcMembers
@_spi(objc)
public class objc_LogEventAttributes: NSObject {
    internal var root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var userAttributes: [String: Any] {
        set { root.swiftModel.attributes.userAttributes = newValue.dd.swiftAttributes }
        get { root.swiftModel.attributes.userAttributes.dd.objCAttributes }
    }
}

@objc(DDLogEventUserInfo)
@objcMembers
@_spi(objc)
public class objc_LogEventUserInfo: NSObject {
    internal var root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var id: String? {
        root.swiftModel.userInfo.id
    }

    public var name: String? {
        root.swiftModel.userInfo.name
    }

    public var email: String? {
        root.swiftModel.userInfo.email
    }

    public var extraInfo: [String: Any] {
        set { root.swiftModel.userInfo.extraInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.userInfo.extraInfo.dd.objCAttributes }
    }
}

@objc(DDLogEventError)
@objcMembers
@_spi(objc)
public class objc_LogEventError: NSObject {
    internal var root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var kind: String? {
        set { root.swiftModel.error?.kind = newValue }
        get { root.swiftModel.error?.kind }
    }

    public var message: String? {
        set { root.swiftModel.error?.message = newValue }
        get { root.swiftModel.error?.message }
    }

    public var stack: String? {
        set { root.swiftModel.error?.stack = newValue }
        get { root.swiftModel.error?.stack }
    }

    public var sourceType: String {
        // swiftlint:disable force_unwrapping
        set { root.swiftModel.error!.sourceType = newValue }
        get { root.swiftModel.error!.sourceType }
        // swiftlint:enable force_unwrapping
    }

    public var fingerprint: String? {
        set { root.swiftModel.error?.fingerprint = newValue }
        get { root.swiftModel.error?.fingerprint }
    }

    public var binaryImages: [objc_LogEventBinaryImage]? {
        set { root.swiftModel.error?.binaryImages = newValue?.map { $0.swiftModel } }
        get { root.swiftModel.error?.binaryImages?.map { objc_LogEventBinaryImage(swiftModel: $0) } }
    }
}

@objc(DDLogEventBinaryImage)
@objcMembers
@_spi(objc)
public class objc_LogEventBinaryImage: NSObject {
    internal let swiftModel: LogEvent.Error.BinaryImage

    internal init(swiftModel: LogEvent.Error.BinaryImage) {
        self.swiftModel = swiftModel
    }

    public var arch: String? {
        swiftModel.arch
    }

    public var isSystem: Bool {
        swiftModel.isSystem
    }

    public var loadAddress: String? {
        swiftModel.loadAddress
    }

    public var maxAddress: String? {
        swiftModel.maxAddress
    }

    public var name: String {
        swiftModel.name
    }

    public var uuid: String {
        swiftModel.uuid
    }
}

@objc(DDLogEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_LogEventOperatingSystem: NSObject {
    internal let root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var name: String {
        root.swiftModel.os.name
    }

    public var version: String {
        root.swiftModel.os.version
    }

    public var build: String? {
        root.swiftModel.os.build
    }
}

@objc(DDLogEventDd)
@objcMembers
@_spi(objc)
public class objc_LogEventDd: NSObject {
    internal let root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var device: objc_LogEventDeviceInfo {
        .init(root: root)
    }
}

@objc(DDLogEventDeviceInfo)
@objcMembers
@_spi(objc)
public class objc_LogEventDeviceInfo: NSObject {
    internal let root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var brand: String {
        root.swiftModel.dd.device.brand
    }

    public var name: String {
        root.swiftModel.dd.device.name
    }

    public var model: String {
        root.swiftModel.dd.device.model
    }

    public var architecture: String {
        root.swiftModel.dd.device.architecture
    }
}

@objc(DDLogEventNetworkConnectionInfo)
@objcMembers
@_spi(objc)
public class objc_LogEventNetworkConnectionInfo: NSObject {
    internal let root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var reachability: objc_LogEventReachability {
        // swiftlint:disable force_unwrapping
        .init(swift: root.swiftModel.networkConnectionInfo!.reachability)
        // swiftlint:enable force_unwrapping
    }

    public var availableInterfaces: [Int]? {
        root.swiftModel.networkConnectionInfo?.availableInterfaces?.map { objc_LogEventInterface(swift: $0).rawValue }
    }

    public var supportsIPv4: NSNumber? {
        root.swiftModel.networkConnectionInfo?.supportsIPv4 as NSNumber?
    }

    public var supportsIPv6: NSNumber? {
        root.swiftModel.networkConnectionInfo?.supportsIPv6 as NSNumber?
    }

    public var isExpensive: NSNumber? {
        root.swiftModel.networkConnectionInfo?.isExpensive as NSNumber?
    }

    public var isConstrained: NSNumber? {
        root.swiftModel.networkConnectionInfo?.isConstrained as NSNumber?
    }
}

@objc(DDLogEventReachability)
@_spi(objc)
public enum objc_LogEventReachability: Int {
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

@objc(DDLogEventInterface)
@_spi(objc)
public enum objc_LogEventInterface: Int {
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

@objc(DDLogEventCarrierInfo)
@objcMembers
@_spi(objc)
public class objc_LogEventCarrierInfo: NSObject {
    internal let root: objc_LogEvent

    internal init(root: objc_LogEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.mobileCarrierInfo?.carrierName
    }

    public var carrierISOCountryCode: String? {
        root.swiftModel.mobileCarrierInfo?.carrierISOCountryCode
    }

    public var carrierAllowsVOIP: Bool {
        // swiftlint:disable force_unwrapping
        root.swiftModel.mobileCarrierInfo!.carrierAllowsVOIP
        // swiftlint:enable force_unwrapping
    }

    public var radioAccessTechnology: objc_LogEventRadioAccessTechnology {
        // swiftlint:disable force_unwrapping
        .init(swift: root.swiftModel.mobileCarrierInfo!.radioAccessTechnology)
        // swiftlint:enable force_unwrapping
    }
}

@objc(DDLogEventRadioAccessTechnology)
@_spi(objc)
public enum objc_LogEventRadioAccessTechnology: Int {
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
