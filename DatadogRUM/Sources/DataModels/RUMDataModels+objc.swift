/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// This file was generated from JSON Schema. Do not modify it directly.

// swiftlint:disable force_unwrapping

@objc(DDRUMActionEvent)
@objcMembers
@_spi(objc)
public class objc_RUMActionEvent: NSObject {
    public internal(set) var swiftModel: RUMActionEvent
    internal var root: objc_RUMActionEvent { self }

    public init(swiftModel: RUMActionEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_RUMActionEventDD {
        objc_RUMActionEventDD(root: root)
    }

    public var account: objc_RUMActionEventRUMAccount? {
        root.swiftModel.account != nil ? objc_RUMActionEventRUMAccount(root: root) : nil
    }

    public var action: objc_RUMActionEventAction {
        objc_RUMActionEventAction(root: root)
    }

    public var application: objc_RUMActionEventApplication {
        objc_RUMActionEventApplication(root: root)
    }

    public var buildId: String? {
        root.swiftModel.buildId
    }

    public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    public var ciTest: objc_RUMActionEventRUMCITest? {
        root.swiftModel.ciTest != nil ? objc_RUMActionEventRUMCITest(root: root) : nil
    }

    public var connectivity: objc_RUMActionEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? objc_RUMActionEventRUMConnectivity(root: root) : nil
    }

    public var container: objc_RUMActionEventContainer? {
        root.swiftModel.container != nil ? objc_RUMActionEventContainer(root: root) : nil
    }

    public var context: objc_RUMActionEventRUMEventAttributes? {
        root.swiftModel.context != nil ? objc_RUMActionEventRUMEventAttributes(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var device: objc_RUMActionEventDevice? {
        root.swiftModel.device != nil ? objc_RUMActionEventDevice(root: root) : nil
    }

    public var display: objc_RUMActionEventDisplay? {
        root.swiftModel.display != nil ? objc_RUMActionEventDisplay(root: root) : nil
    }

    public var os: objc_RUMActionEventOperatingSystem? {
        root.swiftModel.os != nil ? objc_RUMActionEventOperatingSystem(root: root) : nil
    }

    public var service: String? {
        root.swiftModel.service
    }

    public var session: objc_RUMActionEventSession {
        objc_RUMActionEventSession(root: root)
    }

    public var source: objc_RUMActionEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var synthetics: objc_RUMActionEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? objc_RUMActionEventRUMSyntheticsTest(root: root) : nil
    }

    public var type: String {
        root.swiftModel.type
    }

    public var usr: objc_RUMActionEventRUMUser? {
        root.swiftModel.usr != nil ? objc_RUMActionEventRUMUser(root: root) : nil
    }

    public var version: String? {
        root.swiftModel.version
    }

    public var view: objc_RUMActionEventView {
        objc_RUMActionEventView(root: root)
    }
}

@objc(DDRUMActionEventDD)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDD: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var action: objc_RUMActionEventDDAction? {
        root.swiftModel.dd.action != nil ? objc_RUMActionEventDDAction(root: root) : nil
    }

    public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    public var configuration: objc_RUMActionEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? objc_RUMActionEventDDConfiguration(root: root) : nil
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    public var sdkName: String? {
        root.swiftModel.dd.sdkName
    }

    public var session: objc_RUMActionEventDDSession? {
        root.swiftModel.dd.session != nil ? objc_RUMActionEventDDSession(root: root) : nil
    }
}

@objc(DDRUMActionEventDDAction)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDDAction: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var nameSource: objc_RUMActionEventDDActionNameSource {
        set { root.swiftModel.dd.action!.nameSource = newValue.toSwift }
        get { .init(swift: root.swiftModel.dd.action!.nameSource) }
    }

    public var position: objc_RUMActionEventDDActionPosition? {
        root.swiftModel.dd.action!.position != nil ? objc_RUMActionEventDDActionPosition(root: root) : nil
    }

    public var target: objc_RUMActionEventDDActionTarget? {
        root.swiftModel.dd.action!.target != nil ? objc_RUMActionEventDDActionTarget(root: root) : nil
    }
}

@objc(DDRUMActionEventDDActionNameSource)
@_spi(objc)
public enum objc_RUMActionEventDDActionNameSource: Int {
    internal init(swift: RUMActionEvent.DD.Action.NameSource?) {
        switch swift {
        case nil: self = .none
        case .customAttribute?: self = .customAttribute
        case .maskPlaceholder?: self = .maskPlaceholder
        case .standardAttribute?: self = .standardAttribute
        case .textContent?: self = .textContent
        case .maskDisallowed?: self = .maskDisallowed
        case .blank?: self = .blank
        }
    }

    internal var toSwift: RUMActionEvent.DD.Action.NameSource? {
        switch self {
        case .none: return nil
        case .customAttribute: return .customAttribute
        case .maskPlaceholder: return .maskPlaceholder
        case .standardAttribute: return .standardAttribute
        case .textContent: return .textContent
        case .maskDisallowed: return .maskDisallowed
        case .blank: return .blank
        }
    }

    case none
    case customAttribute
    case maskPlaceholder
    case standardAttribute
    case textContent
    case maskDisallowed
    case blank
}

@objc(DDRUMActionEventDDActionPosition)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDDActionPosition: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var x: NSNumber {
        root.swiftModel.dd.action!.position!.x as NSNumber
    }

    public var y: NSNumber {
        root.swiftModel.dd.action!.position!.y as NSNumber
    }
}

@objc(DDRUMActionEventDDActionTarget)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDDActionTarget: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var height: NSNumber? {
        root.swiftModel.dd.action!.target!.height as NSNumber?
    }

    public var selector: String? {
        root.swiftModel.dd.action!.target!.selector
    }

    public var width: NSNumber? {
        root.swiftModel.dd.action!.target!.width as NSNumber?
    }
}

@objc(DDRUMActionEventDDConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDDConfiguration: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var profilingSampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.profilingSampleRate as NSNumber?
    }

    public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc(DDRUMActionEventDDSession)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDDSession: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var plan: objc_RUMActionEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    public var sessionPrecondition: objc_RUMActionEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc(DDRUMActionEventDDSessionPlan)
@_spi(objc)
public enum objc_RUMActionEventDDSessionPlan: Int {
    internal init(swift: RUMActionEvent.DD.Session.Plan?) {
        switch swift {
        case nil: self = .none
        case .plan1?: self = .plan1
        case .plan2?: self = .plan2
        }
    }

    internal var toSwift: RUMActionEvent.DD.Session.Plan? {
        switch self {
        case .none: return nil
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case none
    case plan1
    case plan2
}

@objc(DDRUMActionEventDDSessionRUMSessionPrecondition)
@_spi(objc)
public enum objc_RUMActionEventDDSessionRUMSessionPrecondition: Int {
    internal init(swift: RUMSessionPrecondition?) {
        switch swift {
        case nil: self = .none
        case .userAppLaunch?: self = .userAppLaunch
        case .inactivityTimeout?: self = .inactivityTimeout
        case .maxDuration?: self = .maxDuration
        case .backgroundLaunch?: self = .backgroundLaunch
        case .prewarm?: self = .prewarm
        case .fromNonInteractiveSession?: self = .fromNonInteractiveSession
        case .explicitStop?: self = .explicitStop
        }
    }

    internal var toSwift: RUMSessionPrecondition? {
        switch self {
        case .none: return nil
        case .userAppLaunch: return .userAppLaunch
        case .inactivityTimeout: return .inactivityTimeout
        case .maxDuration: return .maxDuration
        case .backgroundLaunch: return .backgroundLaunch
        case .prewarm: return .prewarm
        case .fromNonInteractiveSession: return .fromNonInteractiveSession
        case .explicitStop: return .explicitStop
        }
    }

    case none
    case userAppLaunch
    case inactivityTimeout
    case maxDuration
    case backgroundLaunch
    case prewarm
    case fromNonInteractiveSession
    case explicitStop
}

@objc(DDRUMActionEventRUMAccount)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMAccount: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.account!.id
    }

    public var name: String? {
        root.swiftModel.account!.name
    }

    public var accountInfo: [String: Any] {
        set { root.swiftModel.account!.accountInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.account!.accountInfo.dd.objCAttributes }
    }
}

@objc(DDRUMActionEventAction)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventAction: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var crash: objc_RUMActionEventActionCrash? {
        root.swiftModel.action.crash != nil ? objc_RUMActionEventActionCrash(root: root) : nil
    }

    public var error: objc_RUMActionEventActionError? {
        root.swiftModel.action.error != nil ? objc_RUMActionEventActionError(root: root) : nil
    }

    public var frustration: objc_RUMActionEventActionFrustration? {
        root.swiftModel.action.frustration != nil ? objc_RUMActionEventActionFrustration(root: root) : nil
    }

    public var id: String? {
        root.swiftModel.action.id
    }

    public var loadingTime: NSNumber? {
        root.swiftModel.action.loadingTime as NSNumber?
    }

    public var longTask: objc_RUMActionEventActionLongTask? {
        root.swiftModel.action.longTask != nil ? objc_RUMActionEventActionLongTask(root: root) : nil
    }

    public var resource: objc_RUMActionEventActionResource? {
        root.swiftModel.action.resource != nil ? objc_RUMActionEventActionResource(root: root) : nil
    }

    public var target: objc_RUMActionEventActionTarget? {
        root.swiftModel.action.target != nil ? objc_RUMActionEventActionTarget(root: root) : nil
    }

    public var type: objc_RUMActionEventActionActionType {
        .init(swift: root.swiftModel.action.type)
    }
}

@objc(DDRUMActionEventActionCrash)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventActionCrash: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.action.crash!.count as NSNumber
    }
}

@objc(DDRUMActionEventActionError)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventActionError: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.action.error!.count as NSNumber
    }
}

@objc(DDRUMActionEventActionFrustration)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventActionFrustration: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var type: [Int] {
        root.swiftModel.action.frustration!.type.map { objc_RUMActionEventActionFrustrationFrustrationType(swift: $0).rawValue }
    }
}

@objc(DDRUMActionEventActionFrustrationFrustrationType)
@_spi(objc)
public enum objc_RUMActionEventActionFrustrationFrustrationType: Int {
    internal init(swift: RUMActionEvent.Action.Frustration.FrustrationType) {
        switch swift {
        case .rageClick: self = .rageClick
        case .deadClick: self = .deadClick
        case .errorClick: self = .errorClick
        case .rageTap: self = .rageTap
        case .errorTap: self = .errorTap
        }
    }

    internal var toSwift: RUMActionEvent.Action.Frustration.FrustrationType {
        switch self {
        case .rageClick: return .rageClick
        case .deadClick: return .deadClick
        case .errorClick: return .errorClick
        case .rageTap: return .rageTap
        case .errorTap: return .errorTap
        }
    }

    case rageClick
    case deadClick
    case errorClick
    case rageTap
    case errorTap
}

@objc(DDRUMActionEventActionLongTask)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventActionLongTask: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.action.longTask!.count as NSNumber
    }
}

@objc(DDRUMActionEventActionResource)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventActionResource: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.action.resource!.count as NSNumber
    }
}

@objc(DDRUMActionEventActionTarget)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventActionTarget: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var name: String {
        set { root.swiftModel.action.target!.name = newValue }
        get { root.swiftModel.action.target!.name }
    }
}

@objc(DDRUMActionEventActionActionType)
@_spi(objc)
public enum objc_RUMActionEventActionActionType: Int {
    internal init(swift: RUMActionEvent.Action.ActionType) {
        switch swift {
        case .custom: self = .custom
        case .click: self = .click
        case .tap: self = .tap
        case .scroll: self = .scroll
        case .swipe: self = .swipe
        case .applicationStart: self = .applicationStart
        case .back: self = .back
        }
    }

    internal var toSwift: RUMActionEvent.Action.ActionType {
        switch self {
        case .custom: return .custom
        case .click: return .click
        case .tap: return .tap
        case .scroll: return .scroll
        case .swipe: return .swipe
        case .applicationStart: return .applicationStart
        case .back: return .back
        }
    }

    case custom
    case click
    case tap
    case scroll
    case swipe
    case applicationStart
    case back
}

@objc(DDRUMActionEventApplication)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventApplication: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var currentLocale: String? {
        root.swiftModel.application.currentLocale
    }

    public var id: String {
        root.swiftModel.application.id
    }
}

@objc(DDRUMActionEventRUMCITest)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMCITest: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc(DDRUMActionEventRUMConnectivity)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMConnectivity: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var cellular: objc_RUMActionEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? objc_RUMActionEventRUMConnectivityCellular(root: root) : nil
    }

    public var effectiveType: objc_RUMActionEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { objc_RUMActionEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    public var status: objc_RUMActionEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc(DDRUMActionEventRUMConnectivityCellular)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMConnectivityCellular: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc(DDRUMActionEventRUMConnectivityEffectiveType)
@_spi(objc)
public enum objc_RUMActionEventRUMConnectivityEffectiveType: Int {
    internal init(swift: RUMConnectivity.EffectiveType?) {
        switch swift {
        case nil: self = .none
        case .slow2g?: self = .slow2g
        case .effectiveType2g?: self = .effectiveType2g
        case .effectiveType3g?: self = .effectiveType3g
        case .effectiveType4g?: self = .effectiveType4g
        }
    }

    internal var toSwift: RUMConnectivity.EffectiveType? {
        switch self {
        case .none: return nil
        case .slow2g: return .slow2g
        case .effectiveType2g: return .effectiveType2g
        case .effectiveType3g: return .effectiveType3g
        case .effectiveType4g: return .effectiveType4g
        }
    }

    case none
    case slow2g
    case effectiveType2g
    case effectiveType3g
    case effectiveType4g
}

@objc(DDRUMActionEventRUMConnectivityInterfaces)
@_spi(objc)
public enum objc_RUMActionEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces?) {
        switch swift {
        case nil: self = .none
        case .bluetooth?: self = .bluetooth
        case .cellular?: self = .cellular
        case .ethernet?: self = .ethernet
        case .wifi?: self = .wifi
        case .wimax?: self = .wimax
        case .mixed?: self = .mixed
        case .other?: self = .other
        case .unknown?: self = .unknown
        case .interfacesNone?: self = .interfacesNone
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces? {
        switch self {
        case .none: return nil
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .interfacesNone: return .interfacesNone
        }
    }

    case none
    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case interfacesNone
}

@objc(DDRUMActionEventRUMConnectivityStatus)
@_spi(objc)
public enum objc_RUMActionEventRUMConnectivityStatus: Int {
    internal init(swift: RUMConnectivity.Status) {
        switch swift {
        case .connected: self = .connected
        case .notConnected: self = .notConnected
        case .maybe: self = .maybe
        }
    }

    internal var toSwift: RUMConnectivity.Status {
        switch self {
        case .connected: return .connected
        case .notConnected: return .notConnected
        case .maybe: return .maybe
        }
    }

    case connected
    case notConnected
    case maybe
}

@objc(DDRUMActionEventContainer)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventContainer: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var source: objc_RUMActionEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    public var view: objc_RUMActionEventContainerView {
        objc_RUMActionEventContainerView(root: root)
    }
}

@objc(DDRUMActionEventContainerSource)
@_spi(objc)
public enum objc_RUMActionEventContainerSource: Int {
    internal init(swift: RUMActionEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMActionEvent.Container.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMActionEventContainerView)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventContainerView: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc(DDRUMActionEventRUMEventAttributes)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMEventAttributes: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var contextInfo: [String: Any] {
        set { root.swiftModel.context!.contextInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.context!.contextInfo.dd.objCAttributes }
    }
}

@objc(DDRUMActionEventDevice)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDevice: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    public var batteryLevel: NSNumber? {
        root.swiftModel.device!.batteryLevel as NSNumber?
    }

    public var brand: String? {
        root.swiftModel.device!.brand
    }

    public var brightnessLevel: NSNumber? {
        root.swiftModel.device!.brightnessLevel as NSNumber?
    }

    public var locale: String? {
        root.swiftModel.device!.locale
    }

    public var locales: [String]? {
        root.swiftModel.device!.locales
    }

    public var model: String? {
        root.swiftModel.device!.model
    }

    public var name: String? {
        root.swiftModel.device!.name
    }

    public var powerSavingMode: NSNumber? {
        root.swiftModel.device!.powerSavingMode as NSNumber?
    }

    public var timeZone: String? {
        root.swiftModel.device!.timeZone
    }

    public var type: objc_RUMActionEventDeviceDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc(DDRUMActionEventDeviceDeviceType)
@_spi(objc)
public enum objc_RUMActionEventDeviceDeviceType: Int {
    internal init(swift: Device.DeviceType?) {
        switch swift {
        case nil: self = .none
        case .mobile?: self = .mobile
        case .desktop?: self = .desktop
        case .tablet?: self = .tablet
        case .tv?: self = .tv
        case .gamingConsole?: self = .gamingConsole
        case .bot?: self = .bot
        case .other?: self = .other
        }
    }

    internal var toSwift: Device.DeviceType? {
        switch self {
        case .none: return nil
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case none
    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc(DDRUMActionEventDisplay)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDisplay: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var viewport: objc_RUMActionEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? objc_RUMActionEventDisplayViewport(root: root) : nil
    }
}

@objc(DDRUMActionEventDisplayViewport)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventDisplayViewport: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc(DDRUMActionEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventOperatingSystem: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.os!.build
    }

    public var name: String {
        root.swiftModel.os!.name
    }

    public var version: String {
        root.swiftModel.os!.version
    }

    public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc(DDRUMActionEventSession)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventSession: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    public var id: String {
        root.swiftModel.session.id
    }

    public var type: objc_RUMActionEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc(DDRUMActionEventSessionRUMSessionType)
@_spi(objc)
public enum objc_RUMActionEventSessionRUMSessionType: Int {
    internal init(swift: RUMSessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMSessionType {
        switch self {
        case .user: return .user
        case .synthetics: return .synthetics
        case .ciTest: return .ciTest
        }
    }

    case user
    case synthetics
    case ciTest
}

@objc(DDRUMActionEventSource)
@_spi(objc)
public enum objc_RUMActionEventSource: Int {
    internal init(swift: RUMActionEvent.Source?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .ios?: self = .ios
        case .browser?: self = .browser
        case .flutter?: self = .flutter
        case .reactNative?: self = .reactNative
        case .roku?: self = .roku
        case .unity?: self = .unity
        case .kotlinMultiplatform?: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMActionEvent.Source? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMActionEventRUMSyntheticsTest)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMSyntheticsTest: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc(DDRUMActionEventRUMUser)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventRUMUser: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var anonymousId: String? {
        root.swiftModel.usr!.anonymousId
    }

    public var email: String? {
        root.swiftModel.usr!.email
    }

    public var id: String? {
        root.swiftModel.usr!.id
    }

    public var name: String? {
        root.swiftModel.usr!.name
    }

    public var usrInfo: [String: Any] {
        set { root.swiftModel.usr!.usrInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.usr!.usrInfo.dd.objCAttributes }
    }
}

@objc(DDRUMActionEventView)
@objcMembers
@_spi(objc)
public class objc_RUMActionEventView: NSObject {
    internal let root: objc_RUMActionEvent

    internal init(root: objc_RUMActionEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view.id
    }

    public var inForeground: NSNumber? {
        root.swiftModel.view.inForeground as NSNumber?
    }

    public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc(DDRUMErrorEvent)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEvent: NSObject {
    public internal(set) var swiftModel: RUMErrorEvent
    internal var root: objc_RUMErrorEvent { self }

    public init(swiftModel: RUMErrorEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_RUMErrorEventDD {
        objc_RUMErrorEventDD(root: root)
    }

    public var account: objc_RUMErrorEventRUMAccount? {
        root.swiftModel.account != nil ? objc_RUMErrorEventRUMAccount(root: root) : nil
    }

    public var action: objc_RUMErrorEventAction? {
        root.swiftModel.action != nil ? objc_RUMErrorEventAction(root: root) : nil
    }

    public var application: objc_RUMErrorEventApplication {
        objc_RUMErrorEventApplication(root: root)
    }

    public var buildId: String? {
        root.swiftModel.buildId
    }

    public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    public var ciTest: objc_RUMErrorEventRUMCITest? {
        root.swiftModel.ciTest != nil ? objc_RUMErrorEventRUMCITest(root: root) : nil
    }

    public var connectivity: objc_RUMErrorEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? objc_RUMErrorEventRUMConnectivity(root: root) : nil
    }

    public var container: objc_RUMErrorEventContainer? {
        root.swiftModel.container != nil ? objc_RUMErrorEventContainer(root: root) : nil
    }

    public var context: objc_RUMErrorEventRUMEventAttributes? {
        root.swiftModel.context != nil ? objc_RUMErrorEventRUMEventAttributes(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var device: objc_RUMErrorEventDevice? {
        root.swiftModel.device != nil ? objc_RUMErrorEventDevice(root: root) : nil
    }

    public var display: objc_RUMErrorEventDisplay? {
        root.swiftModel.display != nil ? objc_RUMErrorEventDisplay(root: root) : nil
    }

    public var error: objc_RUMErrorEventError {
        objc_RUMErrorEventError(root: root)
    }

    public var featureFlags: objc_RUMErrorEventFeatureFlags? {
        root.swiftModel.featureFlags != nil ? objc_RUMErrorEventFeatureFlags(root: root) : nil
    }

    public var freeze: objc_RUMErrorEventFreeze? {
        root.swiftModel.freeze != nil ? objc_RUMErrorEventFreeze(root: root) : nil
    }

    public var os: objc_RUMErrorEventOperatingSystem? {
        root.swiftModel.os != nil ? objc_RUMErrorEventOperatingSystem(root: root) : nil
    }

    public var service: String? {
        root.swiftModel.service
    }

    public var session: objc_RUMErrorEventSession {
        objc_RUMErrorEventSession(root: root)
    }

    public var source: objc_RUMErrorEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var synthetics: objc_RUMErrorEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? objc_RUMErrorEventRUMSyntheticsTest(root: root) : nil
    }

    public var type: String {
        root.swiftModel.type
    }

    public var usr: objc_RUMErrorEventRUMUser? {
        root.swiftModel.usr != nil ? objc_RUMErrorEventRUMUser(root: root) : nil
    }

    public var version: String? {
        root.swiftModel.version
    }

    public var view: objc_RUMErrorEventView {
        objc_RUMErrorEventView(root: root)
    }
}

@objc(DDRUMErrorEventDD)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventDD: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    public var configuration: objc_RUMErrorEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? objc_RUMErrorEventDDConfiguration(root: root) : nil
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    public var sdkName: String? {
        root.swiftModel.dd.sdkName
    }

    public var session: objc_RUMErrorEventDDSession? {
        root.swiftModel.dd.session != nil ? objc_RUMErrorEventDDSession(root: root) : nil
    }
}

@objc(DDRUMErrorEventDDConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventDDConfiguration: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var profilingSampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.profilingSampleRate as NSNumber?
    }

    public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc(DDRUMErrorEventDDSession)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventDDSession: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var plan: objc_RUMErrorEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    public var sessionPrecondition: objc_RUMErrorEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc(DDRUMErrorEventDDSessionPlan)
@_spi(objc)
public enum objc_RUMErrorEventDDSessionPlan: Int {
    internal init(swift: RUMErrorEvent.DD.Session.Plan?) {
        switch swift {
        case nil: self = .none
        case .plan1?: self = .plan1
        case .plan2?: self = .plan2
        }
    }

    internal var toSwift: RUMErrorEvent.DD.Session.Plan? {
        switch self {
        case .none: return nil
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case none
    case plan1
    case plan2
}

@objc(DDRUMErrorEventDDSessionRUMSessionPrecondition)
@_spi(objc)
public enum objc_RUMErrorEventDDSessionRUMSessionPrecondition: Int {
    internal init(swift: RUMSessionPrecondition?) {
        switch swift {
        case nil: self = .none
        case .userAppLaunch?: self = .userAppLaunch
        case .inactivityTimeout?: self = .inactivityTimeout
        case .maxDuration?: self = .maxDuration
        case .backgroundLaunch?: self = .backgroundLaunch
        case .prewarm?: self = .prewarm
        case .fromNonInteractiveSession?: self = .fromNonInteractiveSession
        case .explicitStop?: self = .explicitStop
        }
    }

    internal var toSwift: RUMSessionPrecondition? {
        switch self {
        case .none: return nil
        case .userAppLaunch: return .userAppLaunch
        case .inactivityTimeout: return .inactivityTimeout
        case .maxDuration: return .maxDuration
        case .backgroundLaunch: return .backgroundLaunch
        case .prewarm: return .prewarm
        case .fromNonInteractiveSession: return .fromNonInteractiveSession
        case .explicitStop: return .explicitStop
        }
    }

    case none
    case userAppLaunch
    case inactivityTimeout
    case maxDuration
    case backgroundLaunch
    case prewarm
    case fromNonInteractiveSession
    case explicitStop
}

@objc(DDRUMErrorEventRUMAccount)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMAccount: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.account!.id
    }

    public var name: String? {
        root.swiftModel.account!.name
    }

    public var accountInfo: [String: Any] {
        set { root.swiftModel.account!.accountInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.account!.accountInfo.dd.objCAttributes }
    }
}

@objc(DDRUMErrorEventAction)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventAction: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var id: objc_RUMErrorEventActionRUMActionID {
        objc_RUMErrorEventActionRUMActionID(root: root)
    }
}

@objc(DDRUMErrorEventActionRUMActionID)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventActionRUMActionID: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var string: String? {
        guard case .string(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }

    public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }
}

@objc(DDRUMErrorEventApplication)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventApplication: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var currentLocale: String? {
        root.swiftModel.application.currentLocale
    }

    public var id: String {
        root.swiftModel.application.id
    }
}

@objc(DDRUMErrorEventRUMCITest)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMCITest: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc(DDRUMErrorEventRUMConnectivity)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMConnectivity: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var cellular: objc_RUMErrorEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? objc_RUMErrorEventRUMConnectivityCellular(root: root) : nil
    }

    public var effectiveType: objc_RUMErrorEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { objc_RUMErrorEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    public var status: objc_RUMErrorEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc(DDRUMErrorEventRUMConnectivityCellular)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMConnectivityCellular: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc(DDRUMErrorEventRUMConnectivityEffectiveType)
@_spi(objc)
public enum objc_RUMErrorEventRUMConnectivityEffectiveType: Int {
    internal init(swift: RUMConnectivity.EffectiveType?) {
        switch swift {
        case nil: self = .none
        case .slow2g?: self = .slow2g
        case .effectiveType2g?: self = .effectiveType2g
        case .effectiveType3g?: self = .effectiveType3g
        case .effectiveType4g?: self = .effectiveType4g
        }
    }

    internal var toSwift: RUMConnectivity.EffectiveType? {
        switch self {
        case .none: return nil
        case .slow2g: return .slow2g
        case .effectiveType2g: return .effectiveType2g
        case .effectiveType3g: return .effectiveType3g
        case .effectiveType4g: return .effectiveType4g
        }
    }

    case none
    case slow2g
    case effectiveType2g
    case effectiveType3g
    case effectiveType4g
}

@objc(DDRUMErrorEventRUMConnectivityInterfaces)
@_spi(objc)
public enum objc_RUMErrorEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces?) {
        switch swift {
        case nil: self = .none
        case .bluetooth?: self = .bluetooth
        case .cellular?: self = .cellular
        case .ethernet?: self = .ethernet
        case .wifi?: self = .wifi
        case .wimax?: self = .wimax
        case .mixed?: self = .mixed
        case .other?: self = .other
        case .unknown?: self = .unknown
        case .interfacesNone?: self = .interfacesNone
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces? {
        switch self {
        case .none: return nil
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .interfacesNone: return .interfacesNone
        }
    }

    case none
    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case interfacesNone
}

@objc(DDRUMErrorEventRUMConnectivityStatus)
@_spi(objc)
public enum objc_RUMErrorEventRUMConnectivityStatus: Int {
    internal init(swift: RUMConnectivity.Status) {
        switch swift {
        case .connected: self = .connected
        case .notConnected: self = .notConnected
        case .maybe: self = .maybe
        }
    }

    internal var toSwift: RUMConnectivity.Status {
        switch self {
        case .connected: return .connected
        case .notConnected: return .notConnected
        case .maybe: return .maybe
        }
    }

    case connected
    case notConnected
    case maybe
}

@objc(DDRUMErrorEventContainer)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventContainer: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var source: objc_RUMErrorEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    public var view: objc_RUMErrorEventContainerView {
        objc_RUMErrorEventContainerView(root: root)
    }
}

@objc(DDRUMErrorEventContainerSource)
@_spi(objc)
public enum objc_RUMErrorEventContainerSource: Int {
    internal init(swift: RUMErrorEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMErrorEvent.Container.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMErrorEventContainerView)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventContainerView: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc(DDRUMErrorEventRUMEventAttributes)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMEventAttributes: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var contextInfo: [String: Any] {
        set { root.swiftModel.context!.contextInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.context!.contextInfo.dd.objCAttributes }
    }
}

@objc(DDRUMErrorEventDevice)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventDevice: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    public var batteryLevel: NSNumber? {
        root.swiftModel.device!.batteryLevel as NSNumber?
    }

    public var brand: String? {
        root.swiftModel.device!.brand
    }

    public var brightnessLevel: NSNumber? {
        root.swiftModel.device!.brightnessLevel as NSNumber?
    }

    public var locale: String? {
        root.swiftModel.device!.locale
    }

    public var locales: [String]? {
        root.swiftModel.device!.locales
    }

    public var model: String? {
        root.swiftModel.device!.model
    }

    public var name: String? {
        root.swiftModel.device!.name
    }

    public var powerSavingMode: NSNumber? {
        root.swiftModel.device!.powerSavingMode as NSNumber?
    }

    public var timeZone: String? {
        root.swiftModel.device!.timeZone
    }

    public var type: objc_RUMErrorEventDeviceDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc(DDRUMErrorEventDeviceDeviceType)
@_spi(objc)
public enum objc_RUMErrorEventDeviceDeviceType: Int {
    internal init(swift: Device.DeviceType?) {
        switch swift {
        case nil: self = .none
        case .mobile?: self = .mobile
        case .desktop?: self = .desktop
        case .tablet?: self = .tablet
        case .tv?: self = .tv
        case .gamingConsole?: self = .gamingConsole
        case .bot?: self = .bot
        case .other?: self = .other
        }
    }

    internal var toSwift: Device.DeviceType? {
        switch self {
        case .none: return nil
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case none
    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc(DDRUMErrorEventDisplay)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventDisplay: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var viewport: objc_RUMErrorEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? objc_RUMErrorEventDisplayViewport(root: root) : nil
    }
}

@objc(DDRUMErrorEventDisplayViewport)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventDisplayViewport: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc(DDRUMErrorEventError)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventError: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var binaryImages: [objc_RUMErrorEventErrorBinaryImages]? {
        root.swiftModel.error.binaryImages?.map { objc_RUMErrorEventErrorBinaryImages(swiftModel: $0) }
    }

    public var category: objc_RUMErrorEventErrorCategory {
        .init(swift: root.swiftModel.error.category)
    }

    public var causes: [objc_RUMErrorEventErrorCauses]? {
        set { root.swiftModel.error.causes = newValue?.map { $0.swiftModel } }
        get { root.swiftModel.error.causes?.map { objc_RUMErrorEventErrorCauses(swiftModel: $0) } }
    }

    public var csp: objc_RUMErrorEventErrorCSP? {
        root.swiftModel.error.csp != nil ? objc_RUMErrorEventErrorCSP(root: root) : nil
    }

    public var fingerprint: String? {
        set { root.swiftModel.error.fingerprint = newValue }
        get { root.swiftModel.error.fingerprint }
    }

    public var handling: objc_RUMErrorEventErrorHandling {
        .init(swift: root.swiftModel.error.handling)
    }

    public var handlingStack: String? {
        root.swiftModel.error.handlingStack
    }

    public var id: String? {
        root.swiftModel.error.id
    }

    public var isCrash: NSNumber? {
        root.swiftModel.error.isCrash as NSNumber?
    }

    public var message: String {
        set { root.swiftModel.error.message = newValue }
        get { root.swiftModel.error.message }
    }

    public var meta: objc_RUMErrorEventErrorMeta? {
        root.swiftModel.error.meta != nil ? objc_RUMErrorEventErrorMeta(root: root) : nil
    }

    public var resource: objc_RUMErrorEventErrorResource? {
        root.swiftModel.error.resource != nil ? objc_RUMErrorEventErrorResource(root: root) : nil
    }

    public var source: objc_RUMErrorEventErrorSource {
        .init(swift: root.swiftModel.error.source)
    }

    public var sourceType: objc_RUMErrorEventErrorSourceType {
        .init(swift: root.swiftModel.error.sourceType)
    }

    public var stack: String? {
        set { root.swiftModel.error.stack = newValue }
        get { root.swiftModel.error.stack }
    }

    public var threads: [objc_RUMErrorEventErrorThreads]? {
        root.swiftModel.error.threads?.map { objc_RUMErrorEventErrorThreads(swiftModel: $0) }
    }

    public var timeSinceAppStart: NSNumber? {
        root.swiftModel.error.timeSinceAppStart as NSNumber?
    }

    public var type: String? {
        root.swiftModel.error.type
    }

    public var wasTruncated: NSNumber? {
        root.swiftModel.error.wasTruncated as NSNumber?
    }
}

@objc(DDRUMErrorEventErrorBinaryImages)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorBinaryImages: NSObject {
    internal var swiftModel: RUMErrorEvent.Error.BinaryImages
    internal var root: objc_RUMErrorEventErrorBinaryImages { self }

    internal init(swiftModel: RUMErrorEvent.Error.BinaryImages) {
        self.swiftModel = swiftModel
    }

    public var arch: String? {
        root.swiftModel.arch
    }

    public var isSystem: NSNumber {
        root.swiftModel.isSystem as NSNumber
    }

    public var loadAddress: String? {
        root.swiftModel.loadAddress
    }

    public var maxAddress: String? {
        root.swiftModel.maxAddress
    }

    public var name: String {
        root.swiftModel.name
    }

    public var uuid: String {
        root.swiftModel.uuid
    }
}

@objc(DDRUMErrorEventErrorCategory)
@_spi(objc)
public enum objc_RUMErrorEventErrorCategory: Int {
    internal init(swift: RUMErrorEvent.Error.Category?) {
        switch swift {
        case nil: self = .none
        case .aNR?: self = .aNR
        case .appHang?: self = .appHang
        case .exception?: self = .exception
        case .watchdogTermination?: self = .watchdogTermination
        case .memoryWarning?: self = .memoryWarning
        case .network?: self = .network
        }
    }

    internal var toSwift: RUMErrorEvent.Error.Category? {
        switch self {
        case .none: return nil
        case .aNR: return .aNR
        case .appHang: return .appHang
        case .exception: return .exception
        case .watchdogTermination: return .watchdogTermination
        case .memoryWarning: return .memoryWarning
        case .network: return .network
        }
    }

    case none
    case aNR
    case appHang
    case exception
    case watchdogTermination
    case memoryWarning
    case network
}

@objc(DDRUMErrorEventErrorCauses)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorCauses: NSObject {
    internal var swiftModel: RUMErrorEvent.Error.Causes
    internal var root: objc_RUMErrorEventErrorCauses { self }

    internal init(swiftModel: RUMErrorEvent.Error.Causes) {
        self.swiftModel = swiftModel
    }

    public var message: String {
        set { root.swiftModel.message = newValue }
        get { root.swiftModel.message }
    }

    public var source: objc_RUMErrorEventErrorCausesSource {
        .init(swift: root.swiftModel.source)
    }

    public var stack: String? {
        set { root.swiftModel.stack = newValue }
        get { root.swiftModel.stack }
    }

    public var type: String? {
        root.swiftModel.type
    }
}

@objc(DDRUMErrorEventErrorCausesSource)
@_spi(objc)
public enum objc_RUMErrorEventErrorCausesSource: Int {
    internal init(swift: RUMErrorEvent.Error.Causes.Source) {
        switch swift {
        case .network: self = .network
        case .source: self = .source
        case .console: self = .console
        case .logger: self = .logger
        case .agent: self = .agent
        case .webview: self = .webview
        case .custom: self = .custom
        case .report: self = .report
        }
    }

    internal var toSwift: RUMErrorEvent.Error.Causes.Source {
        switch self {
        case .network: return .network
        case .source: return .source
        case .console: return .console
        case .logger: return .logger
        case .agent: return .agent
        case .webview: return .webview
        case .custom: return .custom
        case .report: return .report
        }
    }

    case network
    case source
    case console
    case logger
    case agent
    case webview
    case custom
    case report
}

@objc(DDRUMErrorEventErrorCSP)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorCSP: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var disposition: objc_RUMErrorEventErrorCSPDisposition {
        .init(swift: root.swiftModel.error.csp!.disposition)
    }
}

@objc(DDRUMErrorEventErrorCSPDisposition)
@_spi(objc)
public enum objc_RUMErrorEventErrorCSPDisposition: Int {
    internal init(swift: RUMErrorEvent.Error.CSP.Disposition?) {
        switch swift {
        case nil: self = .none
        case .enforce?: self = .enforce
        case .report?: self = .report
        }
    }

    internal var toSwift: RUMErrorEvent.Error.CSP.Disposition? {
        switch self {
        case .none: return nil
        case .enforce: return .enforce
        case .report: return .report
        }
    }

    case none
    case enforce
    case report
}

@objc(DDRUMErrorEventErrorHandling)
@_spi(objc)
public enum objc_RUMErrorEventErrorHandling: Int {
    internal init(swift: RUMErrorEvent.Error.Handling?) {
        switch swift {
        case nil: self = .none
        case .handled?: self = .handled
        case .unhandled?: self = .unhandled
        }
    }

    internal var toSwift: RUMErrorEvent.Error.Handling? {
        switch self {
        case .none: return nil
        case .handled: return .handled
        case .unhandled: return .unhandled
        }
    }

    case none
    case handled
    case unhandled
}

@objc(DDRUMErrorEventErrorMeta)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorMeta: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var codeType: String? {
        root.swiftModel.error.meta!.codeType
    }

    public var exceptionCodes: String? {
        root.swiftModel.error.meta!.exceptionCodes
    }

    public var exceptionType: String? {
        root.swiftModel.error.meta!.exceptionType
    }

    public var incidentIdentifier: String? {
        root.swiftModel.error.meta!.incidentIdentifier
    }

    public var parentProcess: String? {
        root.swiftModel.error.meta!.parentProcess
    }

    public var path: String? {
        root.swiftModel.error.meta!.path
    }

    public var process: String? {
        root.swiftModel.error.meta!.process
    }
}

@objc(DDRUMErrorEventErrorResource)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorResource: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var method: objc_RUMErrorEventErrorResourceRUMMethod {
        .init(swift: root.swiftModel.error.resource!.method)
    }

    public var provider: objc_RUMErrorEventErrorResourceProvider? {
        root.swiftModel.error.resource!.provider != nil ? objc_RUMErrorEventErrorResourceProvider(root: root) : nil
    }

    public var statusCode: NSNumber {
        root.swiftModel.error.resource!.statusCode as NSNumber
    }

    public var url: String {
        set { root.swiftModel.error.resource!.url = newValue }
        get { root.swiftModel.error.resource!.url }
    }
}

@objc(DDRUMErrorEventErrorResourceRUMMethod)
@_spi(objc)
public enum objc_RUMErrorEventErrorResourceRUMMethod: Int {
    internal init(swift: RUMMethod) {
        switch swift {
        case .post: self = .post
        case .get: self = .get
        case .head: self = .head
        case .put: self = .put
        case .delete: self = .delete
        case .patch: self = .patch
        case .trace: self = .trace
        case .options: self = .options
        case .connect: self = .connect
        }
    }

    internal var toSwift: RUMMethod {
        switch self {
        case .post: return .post
        case .get: return .get
        case .head: return .head
        case .put: return .put
        case .delete: return .delete
        case .patch: return .patch
        case .trace: return .trace
        case .options: return .options
        case .connect: return .connect
        }
    }

    case post
    case get
    case head
    case put
    case delete
    case patch
    case trace
    case options
    case connect
}

@objc(DDRUMErrorEventErrorResourceProvider)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorResourceProvider: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var domain: String? {
        root.swiftModel.error.resource!.provider!.domain
    }

    public var name: String? {
        root.swiftModel.error.resource!.provider!.name
    }

    public var type: objc_RUMErrorEventErrorResourceProviderProviderType {
        .init(swift: root.swiftModel.error.resource!.provider!.type)
    }
}

@objc(DDRUMErrorEventErrorResourceProviderProviderType)
@_spi(objc)
public enum objc_RUMErrorEventErrorResourceProviderProviderType: Int {
    internal init(swift: RUMErrorEvent.Error.Resource.Provider.ProviderType?) {
        switch swift {
        case nil: self = .none
        case .ad?: self = .ad
        case .advertising?: self = .advertising
        case .analytics?: self = .analytics
        case .cdn?: self = .cdn
        case .content?: self = .content
        case .customerSuccess?: self = .customerSuccess
        case .firstParty?: self = .firstParty
        case .hosting?: self = .hosting
        case .marketing?: self = .marketing
        case .other?: self = .other
        case .social?: self = .social
        case .tagManager?: self = .tagManager
        case .utility?: self = .utility
        case .video?: self = .video
        }
    }

    internal var toSwift: RUMErrorEvent.Error.Resource.Provider.ProviderType? {
        switch self {
        case .none: return nil
        case .ad: return .ad
        case .advertising: return .advertising
        case .analytics: return .analytics
        case .cdn: return .cdn
        case .content: return .content
        case .customerSuccess: return .customerSuccess
        case .firstParty: return .firstParty
        case .hosting: return .hosting
        case .marketing: return .marketing
        case .other: return .other
        case .social: return .social
        case .tagManager: return .tagManager
        case .utility: return .utility
        case .video: return .video
        }
    }

    case none
    case ad
    case advertising
    case analytics
    case cdn
    case content
    case customerSuccess
    case firstParty
    case hosting
    case marketing
    case other
    case social
    case tagManager
    case utility
    case video
}

@objc(DDRUMErrorEventErrorSource)
@_spi(objc)
public enum objc_RUMErrorEventErrorSource: Int {
    internal init(swift: RUMErrorEvent.Error.Source) {
        switch swift {
        case .network: self = .network
        case .source: self = .source
        case .console: self = .console
        case .logger: self = .logger
        case .agent: self = .agent
        case .webview: self = .webview
        case .custom: self = .custom
        case .report: self = .report
        }
    }

    internal var toSwift: RUMErrorEvent.Error.Source {
        switch self {
        case .network: return .network
        case .source: return .source
        case .console: return .console
        case .logger: return .logger
        case .agent: return .agent
        case .webview: return .webview
        case .custom: return .custom
        case .report: return .report
        }
    }

    case network
    case source
    case console
    case logger
    case agent
    case webview
    case custom
    case report
}

@objc(DDRUMErrorEventErrorSourceType)
@_spi(objc)
public enum objc_RUMErrorEventErrorSourceType: Int {
    internal init(swift: RUMErrorEvent.Error.SourceType?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .browser?: self = .browser
        case .ios?: self = .ios
        case .reactNative?: self = .reactNative
        case .flutter?: self = .flutter
        case .roku?: self = .roku
        case .ndk?: self = .ndk
        case .iosIl2cpp?: self = .iosIl2cpp
        case .ndkIl2cpp?: self = .ndkIl2cpp
        }
    }

    internal var toSwift: RUMErrorEvent.Error.SourceType? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .browser: return .browser
        case .ios: return .ios
        case .reactNative: return .reactNative
        case .flutter: return .flutter
        case .roku: return .roku
        case .ndk: return .ndk
        case .iosIl2cpp: return .iosIl2cpp
        case .ndkIl2cpp: return .ndkIl2cpp
        }
    }

    case none
    case android
    case browser
    case ios
    case reactNative
    case flutter
    case roku
    case ndk
    case iosIl2cpp
    case ndkIl2cpp
}

@objc(DDRUMErrorEventErrorThreads)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventErrorThreads: NSObject {
    internal var swiftModel: RUMErrorEvent.Error.Threads
    internal var root: objc_RUMErrorEventErrorThreads { self }

    internal init(swiftModel: RUMErrorEvent.Error.Threads) {
        self.swiftModel = swiftModel
    }

    public var crashed: NSNumber {
        root.swiftModel.crashed as NSNumber
    }

    public var name: String {
        root.swiftModel.name
    }

    public var stack: String {
        root.swiftModel.stack
    }

    public var state: String? {
        root.swiftModel.state
    }
}

@objc(DDRUMErrorEventFeatureFlags)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventFeatureFlags: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var featureFlagsInfo: [String: Any] {
        set { root.swiftModel.featureFlags!.featureFlagsInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.featureFlags!.featureFlagsInfo.dd.objCAttributes }
    }
}

@objc(DDRUMErrorEventFreeze)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventFreeze: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.freeze!.duration as NSNumber
    }
}

@objc(DDRUMErrorEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventOperatingSystem: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.os!.build
    }

    public var name: String {
        root.swiftModel.os!.name
    }

    public var version: String {
        root.swiftModel.os!.version
    }

    public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc(DDRUMErrorEventSession)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventSession: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    public var id: String {
        root.swiftModel.session.id
    }

    public var type: objc_RUMErrorEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc(DDRUMErrorEventSessionRUMSessionType)
@_spi(objc)
public enum objc_RUMErrorEventSessionRUMSessionType: Int {
    internal init(swift: RUMSessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMSessionType {
        switch self {
        case .user: return .user
        case .synthetics: return .synthetics
        case .ciTest: return .ciTest
        }
    }

    case user
    case synthetics
    case ciTest
}

@objc(DDRUMErrorEventSource)
@_spi(objc)
public enum objc_RUMErrorEventSource: Int {
    internal init(swift: RUMErrorEvent.Source?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .ios?: self = .ios
        case .browser?: self = .browser
        case .flutter?: self = .flutter
        case .reactNative?: self = .reactNative
        case .roku?: self = .roku
        case .unity?: self = .unity
        case .kotlinMultiplatform?: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMErrorEvent.Source? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMErrorEventRUMSyntheticsTest)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMSyntheticsTest: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc(DDRUMErrorEventRUMUser)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventRUMUser: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var anonymousId: String? {
        root.swiftModel.usr!.anonymousId
    }

    public var email: String? {
        root.swiftModel.usr!.email
    }

    public var id: String? {
        root.swiftModel.usr!.id
    }

    public var name: String? {
        root.swiftModel.usr!.name
    }

    public var usrInfo: [String: Any] {
        set { root.swiftModel.usr!.usrInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.usr!.usrInfo.dd.objCAttributes }
    }
}

@objc(DDRUMErrorEventView)
@objcMembers
@_spi(objc)
public class objc_RUMErrorEventView: NSObject {
    internal let root: objc_RUMErrorEvent

    internal init(root: objc_RUMErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view.id
    }

    public var inForeground: NSNumber? {
        root.swiftModel.view.inForeground as NSNumber?
    }

    public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc(DDRUMLongTaskEvent)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEvent: NSObject {
    public internal(set) var swiftModel: RUMLongTaskEvent
    internal var root: objc_RUMLongTaskEvent { self }

    public init(swiftModel: RUMLongTaskEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_RUMLongTaskEventDD {
        objc_RUMLongTaskEventDD(root: root)
    }

    public var account: objc_RUMLongTaskEventRUMAccount? {
        root.swiftModel.account != nil ? objc_RUMLongTaskEventRUMAccount(root: root) : nil
    }

    public var action: objc_RUMLongTaskEventAction? {
        root.swiftModel.action != nil ? objc_RUMLongTaskEventAction(root: root) : nil
    }

    public var application: objc_RUMLongTaskEventApplication {
        objc_RUMLongTaskEventApplication(root: root)
    }

    public var buildId: String? {
        root.swiftModel.buildId
    }

    public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    public var ciTest: objc_RUMLongTaskEventRUMCITest? {
        root.swiftModel.ciTest != nil ? objc_RUMLongTaskEventRUMCITest(root: root) : nil
    }

    public var connectivity: objc_RUMLongTaskEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? objc_RUMLongTaskEventRUMConnectivity(root: root) : nil
    }

    public var container: objc_RUMLongTaskEventContainer? {
        root.swiftModel.container != nil ? objc_RUMLongTaskEventContainer(root: root) : nil
    }

    public var context: objc_RUMLongTaskEventRUMEventAttributes? {
        root.swiftModel.context != nil ? objc_RUMLongTaskEventRUMEventAttributes(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var device: objc_RUMLongTaskEventDevice? {
        root.swiftModel.device != nil ? objc_RUMLongTaskEventDevice(root: root) : nil
    }

    public var display: objc_RUMLongTaskEventDisplay? {
        root.swiftModel.display != nil ? objc_RUMLongTaskEventDisplay(root: root) : nil
    }

    public var longTask: objc_RUMLongTaskEventLongTask {
        objc_RUMLongTaskEventLongTask(root: root)
    }

    public var os: objc_RUMLongTaskEventOperatingSystem? {
        root.swiftModel.os != nil ? objc_RUMLongTaskEventOperatingSystem(root: root) : nil
    }

    public var service: String? {
        root.swiftModel.service
    }

    public var session: objc_RUMLongTaskEventSession {
        objc_RUMLongTaskEventSession(root: root)
    }

    public var source: objc_RUMLongTaskEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var synthetics: objc_RUMLongTaskEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? objc_RUMLongTaskEventRUMSyntheticsTest(root: root) : nil
    }

    public var type: String {
        root.swiftModel.type
    }

    public var usr: objc_RUMLongTaskEventRUMUser? {
        root.swiftModel.usr != nil ? objc_RUMLongTaskEventRUMUser(root: root) : nil
    }

    public var version: String? {
        root.swiftModel.version
    }

    public var view: objc_RUMLongTaskEventView {
        objc_RUMLongTaskEventView(root: root)
    }
}

@objc(DDRUMLongTaskEventDD)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDD: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    public var configuration: objc_RUMLongTaskEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? objc_RUMLongTaskEventDDConfiguration(root: root) : nil
    }

    public var discarded: NSNumber? {
        root.swiftModel.dd.discarded as NSNumber?
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    public var profiling: objc_RUMLongTaskEventDDProfiling? {
        root.swiftModel.dd.profiling != nil ? objc_RUMLongTaskEventDDProfiling(root: root) : nil
    }

    public var sdkName: String? {
        root.swiftModel.dd.sdkName
    }

    public var session: objc_RUMLongTaskEventDDSession? {
        root.swiftModel.dd.session != nil ? objc_RUMLongTaskEventDDSession(root: root) : nil
    }
}

@objc(DDRUMLongTaskEventDDConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDDConfiguration: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var profilingSampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.profilingSampleRate as NSNumber?
    }

    public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc(DDRUMLongTaskEventDDProfiling)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDDProfiling: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var errorReason: objc_RUMLongTaskEventDDProfilingErrorReason {
        .init(swift: root.swiftModel.dd.profiling!.errorReason)
    }

    public var status: objc_RUMLongTaskEventDDProfilingStatus {
        .init(swift: root.swiftModel.dd.profiling!.status)
    }
}

@objc(DDRUMLongTaskEventDDProfilingErrorReason)
@_spi(objc)
public enum objc_RUMLongTaskEventDDProfilingErrorReason: Int {
    internal init(swift: RUMLongTaskEvent.DD.Profiling.ErrorReason?) {
        switch swift {
        case nil: self = .none
        case .notSupportedByBrowser?: self = .notSupportedByBrowser
        case .failedToLazyLoad?: self = .failedToLazyLoad
        case .missingDocumentPolicyHeader?: self = .missingDocumentPolicyHeader
        case .unexpectedException?: self = .unexpectedException
        }
    }

    internal var toSwift: RUMLongTaskEvent.DD.Profiling.ErrorReason? {
        switch self {
        case .none: return nil
        case .notSupportedByBrowser: return .notSupportedByBrowser
        case .failedToLazyLoad: return .failedToLazyLoad
        case .missingDocumentPolicyHeader: return .missingDocumentPolicyHeader
        case .unexpectedException: return .unexpectedException
        }
    }

    case none
    case notSupportedByBrowser
    case failedToLazyLoad
    case missingDocumentPolicyHeader
    case unexpectedException
}

@objc(DDRUMLongTaskEventDDProfilingStatus)
@_spi(objc)
public enum objc_RUMLongTaskEventDDProfilingStatus: Int {
    internal init(swift: RUMLongTaskEvent.DD.Profiling.Status?) {
        switch swift {
        case nil: self = .none
        case .starting?: self = .starting
        case .running?: self = .running
        case .stopped?: self = .stopped
        case .error?: self = .error
        }
    }

    internal var toSwift: RUMLongTaskEvent.DD.Profiling.Status? {
        switch self {
        case .none: return nil
        case .starting: return .starting
        case .running: return .running
        case .stopped: return .stopped
        case .error: return .error
        }
    }

    case none
    case starting
    case running
    case stopped
    case error
}

@objc(DDRUMLongTaskEventDDSession)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDDSession: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var plan: objc_RUMLongTaskEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    public var sessionPrecondition: objc_RUMLongTaskEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc(DDRUMLongTaskEventDDSessionPlan)
@_spi(objc)
public enum objc_RUMLongTaskEventDDSessionPlan: Int {
    internal init(swift: RUMLongTaskEvent.DD.Session.Plan?) {
        switch swift {
        case nil: self = .none
        case .plan1?: self = .plan1
        case .plan2?: self = .plan2
        }
    }

    internal var toSwift: RUMLongTaskEvent.DD.Session.Plan? {
        switch self {
        case .none: return nil
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case none
    case plan1
    case plan2
}

@objc(DDRUMLongTaskEventDDSessionRUMSessionPrecondition)
@_spi(objc)
public enum objc_RUMLongTaskEventDDSessionRUMSessionPrecondition: Int {
    internal init(swift: RUMSessionPrecondition?) {
        switch swift {
        case nil: self = .none
        case .userAppLaunch?: self = .userAppLaunch
        case .inactivityTimeout?: self = .inactivityTimeout
        case .maxDuration?: self = .maxDuration
        case .backgroundLaunch?: self = .backgroundLaunch
        case .prewarm?: self = .prewarm
        case .fromNonInteractiveSession?: self = .fromNonInteractiveSession
        case .explicitStop?: self = .explicitStop
        }
    }

    internal var toSwift: RUMSessionPrecondition? {
        switch self {
        case .none: return nil
        case .userAppLaunch: return .userAppLaunch
        case .inactivityTimeout: return .inactivityTimeout
        case .maxDuration: return .maxDuration
        case .backgroundLaunch: return .backgroundLaunch
        case .prewarm: return .prewarm
        case .fromNonInteractiveSession: return .fromNonInteractiveSession
        case .explicitStop: return .explicitStop
        }
    }

    case none
    case userAppLaunch
    case inactivityTimeout
    case maxDuration
    case backgroundLaunch
    case prewarm
    case fromNonInteractiveSession
    case explicitStop
}

@objc(DDRUMLongTaskEventRUMAccount)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMAccount: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.account!.id
    }

    public var name: String? {
        root.swiftModel.account!.name
    }

    public var accountInfo: [String: Any] {
        set { root.swiftModel.account!.accountInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.account!.accountInfo.dd.objCAttributes }
    }
}

@objc(DDRUMLongTaskEventAction)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventAction: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var id: objc_RUMLongTaskEventActionRUMActionID {
        objc_RUMLongTaskEventActionRUMActionID(root: root)
    }
}

@objc(DDRUMLongTaskEventActionRUMActionID)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventActionRUMActionID: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var string: String? {
        guard case .string(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }

    public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }
}

@objc(DDRUMLongTaskEventApplication)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventApplication: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var currentLocale: String? {
        root.swiftModel.application.currentLocale
    }

    public var id: String {
        root.swiftModel.application.id
    }
}

@objc(DDRUMLongTaskEventRUMCITest)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMCITest: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc(DDRUMLongTaskEventRUMConnectivity)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMConnectivity: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var cellular: objc_RUMLongTaskEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? objc_RUMLongTaskEventRUMConnectivityCellular(root: root) : nil
    }

    public var effectiveType: objc_RUMLongTaskEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { objc_RUMLongTaskEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    public var status: objc_RUMLongTaskEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc(DDRUMLongTaskEventRUMConnectivityCellular)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMConnectivityCellular: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc(DDRUMLongTaskEventRUMConnectivityEffectiveType)
@_spi(objc)
public enum objc_RUMLongTaskEventRUMConnectivityEffectiveType: Int {
    internal init(swift: RUMConnectivity.EffectiveType?) {
        switch swift {
        case nil: self = .none
        case .slow2g?: self = .slow2g
        case .effectiveType2g?: self = .effectiveType2g
        case .effectiveType3g?: self = .effectiveType3g
        case .effectiveType4g?: self = .effectiveType4g
        }
    }

    internal var toSwift: RUMConnectivity.EffectiveType? {
        switch self {
        case .none: return nil
        case .slow2g: return .slow2g
        case .effectiveType2g: return .effectiveType2g
        case .effectiveType3g: return .effectiveType3g
        case .effectiveType4g: return .effectiveType4g
        }
    }

    case none
    case slow2g
    case effectiveType2g
    case effectiveType3g
    case effectiveType4g
}

@objc(DDRUMLongTaskEventRUMConnectivityInterfaces)
@_spi(objc)
public enum objc_RUMLongTaskEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces?) {
        switch swift {
        case nil: self = .none
        case .bluetooth?: self = .bluetooth
        case .cellular?: self = .cellular
        case .ethernet?: self = .ethernet
        case .wifi?: self = .wifi
        case .wimax?: self = .wimax
        case .mixed?: self = .mixed
        case .other?: self = .other
        case .unknown?: self = .unknown
        case .interfacesNone?: self = .interfacesNone
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces? {
        switch self {
        case .none: return nil
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .interfacesNone: return .interfacesNone
        }
    }

    case none
    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case interfacesNone
}

@objc(DDRUMLongTaskEventRUMConnectivityStatus)
@_spi(objc)
public enum objc_RUMLongTaskEventRUMConnectivityStatus: Int {
    internal init(swift: RUMConnectivity.Status) {
        switch swift {
        case .connected: self = .connected
        case .notConnected: self = .notConnected
        case .maybe: self = .maybe
        }
    }

    internal var toSwift: RUMConnectivity.Status {
        switch self {
        case .connected: return .connected
        case .notConnected: return .notConnected
        case .maybe: return .maybe
        }
    }

    case connected
    case notConnected
    case maybe
}

@objc(DDRUMLongTaskEventContainer)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventContainer: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var source: objc_RUMLongTaskEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    public var view: objc_RUMLongTaskEventContainerView {
        objc_RUMLongTaskEventContainerView(root: root)
    }
}

@objc(DDRUMLongTaskEventContainerSource)
@_spi(objc)
public enum objc_RUMLongTaskEventContainerSource: Int {
    internal init(swift: RUMLongTaskEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMLongTaskEvent.Container.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMLongTaskEventContainerView)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventContainerView: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc(DDRUMLongTaskEventRUMEventAttributes)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMEventAttributes: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var contextInfo: [String: Any] {
        set { root.swiftModel.context!.contextInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.context!.contextInfo.dd.objCAttributes }
    }
}

@objc(DDRUMLongTaskEventDevice)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDevice: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    public var batteryLevel: NSNumber? {
        root.swiftModel.device!.batteryLevel as NSNumber?
    }

    public var brand: String? {
        root.swiftModel.device!.brand
    }

    public var brightnessLevel: NSNumber? {
        root.swiftModel.device!.brightnessLevel as NSNumber?
    }

    public var locale: String? {
        root.swiftModel.device!.locale
    }

    public var locales: [String]? {
        root.swiftModel.device!.locales
    }

    public var model: String? {
        root.swiftModel.device!.model
    }

    public var name: String? {
        root.swiftModel.device!.name
    }

    public var powerSavingMode: NSNumber? {
        root.swiftModel.device!.powerSavingMode as NSNumber?
    }

    public var timeZone: String? {
        root.swiftModel.device!.timeZone
    }

    public var type: objc_RUMLongTaskEventDeviceDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc(DDRUMLongTaskEventDeviceDeviceType)
@_spi(objc)
public enum objc_RUMLongTaskEventDeviceDeviceType: Int {
    internal init(swift: Device.DeviceType?) {
        switch swift {
        case nil: self = .none
        case .mobile?: self = .mobile
        case .desktop?: self = .desktop
        case .tablet?: self = .tablet
        case .tv?: self = .tv
        case .gamingConsole?: self = .gamingConsole
        case .bot?: self = .bot
        case .other?: self = .other
        }
    }

    internal var toSwift: Device.DeviceType? {
        switch self {
        case .none: return nil
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case none
    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc(DDRUMLongTaskEventDisplay)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDisplay: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var viewport: objc_RUMLongTaskEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? objc_RUMLongTaskEventDisplayViewport(root: root) : nil
    }
}

@objc(DDRUMLongTaskEventDisplayViewport)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventDisplayViewport: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc(DDRUMLongTaskEventLongTask)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventLongTask: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var blockingDuration: NSNumber? {
        root.swiftModel.longTask.blockingDuration as NSNumber?
    }

    public var duration: NSNumber {
        root.swiftModel.longTask.duration as NSNumber
    }

    public var entryType: objc_RUMLongTaskEventLongTaskEntryType {
        .init(swift: root.swiftModel.longTask.entryType)
    }

    public var firstUiEventTimestamp: NSNumber? {
        root.swiftModel.longTask.firstUiEventTimestamp as NSNumber?
    }

    public var id: String? {
        root.swiftModel.longTask.id
    }

    public var isFrozenFrame: NSNumber? {
        root.swiftModel.longTask.isFrozenFrame as NSNumber?
    }

    public var renderStart: NSNumber? {
        root.swiftModel.longTask.renderStart as NSNumber?
    }

    public var scripts: [objc_RUMLongTaskEventLongTaskScripts]? {
        root.swiftModel.longTask.scripts?.map { objc_RUMLongTaskEventLongTaskScripts(swiftModel: $0) }
    }

    public var startTime: NSNumber? {
        root.swiftModel.longTask.startTime as NSNumber?
    }

    public var styleAndLayoutStart: NSNumber? {
        root.swiftModel.longTask.styleAndLayoutStart as NSNumber?
    }
}

@objc(DDRUMLongTaskEventLongTaskEntryType)
@_spi(objc)
public enum objc_RUMLongTaskEventLongTaskEntryType: Int {
    internal init(swift: RUMLongTaskEvent.LongTask.EntryType?) {
        switch swift {
        case nil: self = .none
        case .longTask?: self = .longTask
        case .longAnimationFrame?: self = .longAnimationFrame
        }
    }

    internal var toSwift: RUMLongTaskEvent.LongTask.EntryType? {
        switch self {
        case .none: return nil
        case .longTask: return .longTask
        case .longAnimationFrame: return .longAnimationFrame
        }
    }

    case none
    case longTask
    case longAnimationFrame
}

@objc(DDRUMLongTaskEventLongTaskScripts)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventLongTaskScripts: NSObject {
    internal var swiftModel: RUMLongTaskEvent.LongTask.Scripts
    internal var root: objc_RUMLongTaskEventLongTaskScripts { self }

    internal init(swiftModel: RUMLongTaskEvent.LongTask.Scripts) {
        self.swiftModel = swiftModel
    }

    public var duration: NSNumber? {
        root.swiftModel.duration as NSNumber?
    }

    public var executionStart: NSNumber? {
        root.swiftModel.executionStart as NSNumber?
    }

    public var forcedStyleAndLayoutDuration: NSNumber? {
        root.swiftModel.forcedStyleAndLayoutDuration as NSNumber?
    }

    public var invoker: String? {
        root.swiftModel.invoker
    }

    public var invokerType: objc_RUMLongTaskEventLongTaskScriptsInvokerType {
        .init(swift: root.swiftModel.invokerType)
    }

    public var pauseDuration: NSNumber? {
        root.swiftModel.pauseDuration as NSNumber?
    }

    public var sourceCharPosition: NSNumber? {
        root.swiftModel.sourceCharPosition as NSNumber?
    }

    public var sourceFunctionName: String? {
        root.swiftModel.sourceFunctionName
    }

    public var sourceUrl: String? {
        root.swiftModel.sourceUrl
    }

    public var startTime: NSNumber? {
        root.swiftModel.startTime as NSNumber?
    }

    public var windowAttribution: String? {
        root.swiftModel.windowAttribution
    }
}

@objc(DDRUMLongTaskEventLongTaskScriptsInvokerType)
@_spi(objc)
public enum objc_RUMLongTaskEventLongTaskScriptsInvokerType: Int {
    internal init(swift: RUMLongTaskEvent.LongTask.Scripts.InvokerType?) {
        switch swift {
        case nil: self = .none
        case .userCallback?: self = .userCallback
        case .eventListener?: self = .eventListener
        case .resolvePromise?: self = .resolvePromise
        case .rejectPromise?: self = .rejectPromise
        case .classicScript?: self = .classicScript
        case .moduleScript?: self = .moduleScript
        }
    }

    internal var toSwift: RUMLongTaskEvent.LongTask.Scripts.InvokerType? {
        switch self {
        case .none: return nil
        case .userCallback: return .userCallback
        case .eventListener: return .eventListener
        case .resolvePromise: return .resolvePromise
        case .rejectPromise: return .rejectPromise
        case .classicScript: return .classicScript
        case .moduleScript: return .moduleScript
        }
    }

    case none
    case userCallback
    case eventListener
    case resolvePromise
    case rejectPromise
    case classicScript
    case moduleScript
}

@objc(DDRUMLongTaskEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventOperatingSystem: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.os!.build
    }

    public var name: String {
        root.swiftModel.os!.name
    }

    public var version: String {
        root.swiftModel.os!.version
    }

    public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc(DDRUMLongTaskEventSession)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventSession: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    public var id: String {
        root.swiftModel.session.id
    }

    public var type: objc_RUMLongTaskEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc(DDRUMLongTaskEventSessionRUMSessionType)
@_spi(objc)
public enum objc_RUMLongTaskEventSessionRUMSessionType: Int {
    internal init(swift: RUMSessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMSessionType {
        switch self {
        case .user: return .user
        case .synthetics: return .synthetics
        case .ciTest: return .ciTest
        }
    }

    case user
    case synthetics
    case ciTest
}

@objc(DDRUMLongTaskEventSource)
@_spi(objc)
public enum objc_RUMLongTaskEventSource: Int {
    internal init(swift: RUMLongTaskEvent.Source?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .ios?: self = .ios
        case .browser?: self = .browser
        case .flutter?: self = .flutter
        case .reactNative?: self = .reactNative
        case .roku?: self = .roku
        case .unity?: self = .unity
        case .kotlinMultiplatform?: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMLongTaskEvent.Source? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMLongTaskEventRUMSyntheticsTest)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMSyntheticsTest: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc(DDRUMLongTaskEventRUMUser)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventRUMUser: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var anonymousId: String? {
        root.swiftModel.usr!.anonymousId
    }

    public var email: String? {
        root.swiftModel.usr!.email
    }

    public var id: String? {
        root.swiftModel.usr!.id
    }

    public var name: String? {
        root.swiftModel.usr!.name
    }

    public var usrInfo: [String: Any] {
        set { root.swiftModel.usr!.usrInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.usr!.usrInfo.dd.objCAttributes }
    }
}

@objc(DDRUMLongTaskEventView)
@objcMembers
@_spi(objc)
public class objc_RUMLongTaskEventView: NSObject {
    internal let root: objc_RUMLongTaskEvent

    internal init(root: objc_RUMLongTaskEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view.id
    }

    public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc(DDRUMResourceEvent)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEvent: NSObject {
    public internal(set) var swiftModel: RUMResourceEvent
    internal var root: objc_RUMResourceEvent { self }

    public init(swiftModel: RUMResourceEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_RUMResourceEventDD {
        objc_RUMResourceEventDD(root: root)
    }

    public var account: objc_RUMResourceEventRUMAccount? {
        root.swiftModel.account != nil ? objc_RUMResourceEventRUMAccount(root: root) : nil
    }

    public var action: objc_RUMResourceEventAction? {
        root.swiftModel.action != nil ? objc_RUMResourceEventAction(root: root) : nil
    }

    public var application: objc_RUMResourceEventApplication {
        objc_RUMResourceEventApplication(root: root)
    }

    public var buildId: String? {
        root.swiftModel.buildId
    }

    public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    public var ciTest: objc_RUMResourceEventRUMCITest? {
        root.swiftModel.ciTest != nil ? objc_RUMResourceEventRUMCITest(root: root) : nil
    }

    public var connectivity: objc_RUMResourceEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? objc_RUMResourceEventRUMConnectivity(root: root) : nil
    }

    public var container: objc_RUMResourceEventContainer? {
        root.swiftModel.container != nil ? objc_RUMResourceEventContainer(root: root) : nil
    }

    public var context: objc_RUMResourceEventRUMEventAttributes? {
        root.swiftModel.context != nil ? objc_RUMResourceEventRUMEventAttributes(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var device: objc_RUMResourceEventDevice? {
        root.swiftModel.device != nil ? objc_RUMResourceEventDevice(root: root) : nil
    }

    public var display: objc_RUMResourceEventDisplay? {
        root.swiftModel.display != nil ? objc_RUMResourceEventDisplay(root: root) : nil
    }

    public var os: objc_RUMResourceEventOperatingSystem? {
        root.swiftModel.os != nil ? objc_RUMResourceEventOperatingSystem(root: root) : nil
    }

    public var resource: objc_RUMResourceEventResource {
        objc_RUMResourceEventResource(root: root)
    }

    public var service: String? {
        root.swiftModel.service
    }

    public var session: objc_RUMResourceEventSession {
        objc_RUMResourceEventSession(root: root)
    }

    public var source: objc_RUMResourceEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var synthetics: objc_RUMResourceEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? objc_RUMResourceEventRUMSyntheticsTest(root: root) : nil
    }

    public var type: String {
        root.swiftModel.type
    }

    public var usr: objc_RUMResourceEventRUMUser? {
        root.swiftModel.usr != nil ? objc_RUMResourceEventRUMUser(root: root) : nil
    }

    public var version: String? {
        root.swiftModel.version
    }

    public var view: objc_RUMResourceEventView {
        objc_RUMResourceEventView(root: root)
    }
}

@objc(DDRUMResourceEventDD)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventDD: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    public var configuration: objc_RUMResourceEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? objc_RUMResourceEventDDConfiguration(root: root) : nil
    }

    public var discarded: NSNumber? {
        root.swiftModel.dd.discarded as NSNumber?
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    public var rulePsr: NSNumber? {
        root.swiftModel.dd.rulePsr as NSNumber?
    }

    public var sdkName: String? {
        root.swiftModel.dd.sdkName
    }

    public var session: objc_RUMResourceEventDDSession? {
        root.swiftModel.dd.session != nil ? objc_RUMResourceEventDDSession(root: root) : nil
    }

    public var spanId: String? {
        root.swiftModel.dd.spanId
    }

    public var traceId: String? {
        root.swiftModel.dd.traceId
    }
}

@objc(DDRUMResourceEventDDConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventDDConfiguration: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var profilingSampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.profilingSampleRate as NSNumber?
    }

    public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc(DDRUMResourceEventDDSession)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventDDSession: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var plan: objc_RUMResourceEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    public var sessionPrecondition: objc_RUMResourceEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc(DDRUMResourceEventDDSessionPlan)
@_spi(objc)
public enum objc_RUMResourceEventDDSessionPlan: Int {
    internal init(swift: RUMResourceEvent.DD.Session.Plan?) {
        switch swift {
        case nil: self = .none
        case .plan1?: self = .plan1
        case .plan2?: self = .plan2
        }
    }

    internal var toSwift: RUMResourceEvent.DD.Session.Plan? {
        switch self {
        case .none: return nil
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case none
    case plan1
    case plan2
}

@objc(DDRUMResourceEventDDSessionRUMSessionPrecondition)
@_spi(objc)
public enum objc_RUMResourceEventDDSessionRUMSessionPrecondition: Int {
    internal init(swift: RUMSessionPrecondition?) {
        switch swift {
        case nil: self = .none
        case .userAppLaunch?: self = .userAppLaunch
        case .inactivityTimeout?: self = .inactivityTimeout
        case .maxDuration?: self = .maxDuration
        case .backgroundLaunch?: self = .backgroundLaunch
        case .prewarm?: self = .prewarm
        case .fromNonInteractiveSession?: self = .fromNonInteractiveSession
        case .explicitStop?: self = .explicitStop
        }
    }

    internal var toSwift: RUMSessionPrecondition? {
        switch self {
        case .none: return nil
        case .userAppLaunch: return .userAppLaunch
        case .inactivityTimeout: return .inactivityTimeout
        case .maxDuration: return .maxDuration
        case .backgroundLaunch: return .backgroundLaunch
        case .prewarm: return .prewarm
        case .fromNonInteractiveSession: return .fromNonInteractiveSession
        case .explicitStop: return .explicitStop
        }
    }

    case none
    case userAppLaunch
    case inactivityTimeout
    case maxDuration
    case backgroundLaunch
    case prewarm
    case fromNonInteractiveSession
    case explicitStop
}

@objc(DDRUMResourceEventRUMAccount)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMAccount: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.account!.id
    }

    public var name: String? {
        root.swiftModel.account!.name
    }

    public var accountInfo: [String: Any] {
        set { root.swiftModel.account!.accountInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.account!.accountInfo.dd.objCAttributes }
    }
}

@objc(DDRUMResourceEventAction)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventAction: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var id: objc_RUMResourceEventActionRUMActionID {
        objc_RUMResourceEventActionRUMActionID(root: root)
    }
}

@objc(DDRUMResourceEventActionRUMActionID)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventActionRUMActionID: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var string: String? {
        guard case .string(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }

    public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }
}

@objc(DDRUMResourceEventApplication)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventApplication: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var currentLocale: String? {
        root.swiftModel.application.currentLocale
    }

    public var id: String {
        root.swiftModel.application.id
    }
}

@objc(DDRUMResourceEventRUMCITest)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMCITest: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc(DDRUMResourceEventRUMConnectivity)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMConnectivity: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var cellular: objc_RUMResourceEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? objc_RUMResourceEventRUMConnectivityCellular(root: root) : nil
    }

    public var effectiveType: objc_RUMResourceEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { objc_RUMResourceEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    public var status: objc_RUMResourceEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc(DDRUMResourceEventRUMConnectivityCellular)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMConnectivityCellular: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc(DDRUMResourceEventRUMConnectivityEffectiveType)
@_spi(objc)
public enum objc_RUMResourceEventRUMConnectivityEffectiveType: Int {
    internal init(swift: RUMConnectivity.EffectiveType?) {
        switch swift {
        case nil: self = .none
        case .slow2g?: self = .slow2g
        case .effectiveType2g?: self = .effectiveType2g
        case .effectiveType3g?: self = .effectiveType3g
        case .effectiveType4g?: self = .effectiveType4g
        }
    }

    internal var toSwift: RUMConnectivity.EffectiveType? {
        switch self {
        case .none: return nil
        case .slow2g: return .slow2g
        case .effectiveType2g: return .effectiveType2g
        case .effectiveType3g: return .effectiveType3g
        case .effectiveType4g: return .effectiveType4g
        }
    }

    case none
    case slow2g
    case effectiveType2g
    case effectiveType3g
    case effectiveType4g
}

@objc(DDRUMResourceEventRUMConnectivityInterfaces)
@_spi(objc)
public enum objc_RUMResourceEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces?) {
        switch swift {
        case nil: self = .none
        case .bluetooth?: self = .bluetooth
        case .cellular?: self = .cellular
        case .ethernet?: self = .ethernet
        case .wifi?: self = .wifi
        case .wimax?: self = .wimax
        case .mixed?: self = .mixed
        case .other?: self = .other
        case .unknown?: self = .unknown
        case .interfacesNone?: self = .interfacesNone
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces? {
        switch self {
        case .none: return nil
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .interfacesNone: return .interfacesNone
        }
    }

    case none
    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case interfacesNone
}

@objc(DDRUMResourceEventRUMConnectivityStatus)
@_spi(objc)
public enum objc_RUMResourceEventRUMConnectivityStatus: Int {
    internal init(swift: RUMConnectivity.Status) {
        switch swift {
        case .connected: self = .connected
        case .notConnected: self = .notConnected
        case .maybe: self = .maybe
        }
    }

    internal var toSwift: RUMConnectivity.Status {
        switch self {
        case .connected: return .connected
        case .notConnected: return .notConnected
        case .maybe: return .maybe
        }
    }

    case connected
    case notConnected
    case maybe
}

@objc(DDRUMResourceEventContainer)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventContainer: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var source: objc_RUMResourceEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    public var view: objc_RUMResourceEventContainerView {
        objc_RUMResourceEventContainerView(root: root)
    }
}

@objc(DDRUMResourceEventContainerSource)
@_spi(objc)
public enum objc_RUMResourceEventContainerSource: Int {
    internal init(swift: RUMResourceEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMResourceEvent.Container.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMResourceEventContainerView)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventContainerView: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc(DDRUMResourceEventRUMEventAttributes)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMEventAttributes: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var contextInfo: [String: Any] {
        set { root.swiftModel.context!.contextInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.context!.contextInfo.dd.objCAttributes }
    }
}

@objc(DDRUMResourceEventDevice)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventDevice: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    public var batteryLevel: NSNumber? {
        root.swiftModel.device!.batteryLevel as NSNumber?
    }

    public var brand: String? {
        root.swiftModel.device!.brand
    }

    public var brightnessLevel: NSNumber? {
        root.swiftModel.device!.brightnessLevel as NSNumber?
    }

    public var locale: String? {
        root.swiftModel.device!.locale
    }

    public var locales: [String]? {
        root.swiftModel.device!.locales
    }

    public var model: String? {
        root.swiftModel.device!.model
    }

    public var name: String? {
        root.swiftModel.device!.name
    }

    public var powerSavingMode: NSNumber? {
        root.swiftModel.device!.powerSavingMode as NSNumber?
    }

    public var timeZone: String? {
        root.swiftModel.device!.timeZone
    }

    public var type: objc_RUMResourceEventDeviceDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc(DDRUMResourceEventDeviceDeviceType)
@_spi(objc)
public enum objc_RUMResourceEventDeviceDeviceType: Int {
    internal init(swift: Device.DeviceType?) {
        switch swift {
        case nil: self = .none
        case .mobile?: self = .mobile
        case .desktop?: self = .desktop
        case .tablet?: self = .tablet
        case .tv?: self = .tv
        case .gamingConsole?: self = .gamingConsole
        case .bot?: self = .bot
        case .other?: self = .other
        }
    }

    internal var toSwift: Device.DeviceType? {
        switch self {
        case .none: return nil
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case none
    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc(DDRUMResourceEventDisplay)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventDisplay: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var viewport: objc_RUMResourceEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? objc_RUMResourceEventDisplayViewport(root: root) : nil
    }
}

@objc(DDRUMResourceEventDisplayViewport)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventDisplayViewport: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc(DDRUMResourceEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventOperatingSystem: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.os!.build
    }

    public var name: String {
        root.swiftModel.os!.name
    }

    public var version: String {
        root.swiftModel.os!.version
    }

    public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc(DDRUMResourceEventResource)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResource: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var connect: objc_RUMResourceEventResourceConnect? {
        root.swiftModel.resource.connect != nil ? objc_RUMResourceEventResourceConnect(root: root) : nil
    }

    public var decodedBodySize: NSNumber? {
        root.swiftModel.resource.decodedBodySize as NSNumber?
    }

    public var deliveryType: objc_RUMResourceEventResourceDeliveryType {
        .init(swift: root.swiftModel.resource.deliveryType)
    }

    public var dns: objc_RUMResourceEventResourceDNS? {
        root.swiftModel.resource.dns != nil ? objc_RUMResourceEventResourceDNS(root: root) : nil
    }

    public var download: objc_RUMResourceEventResourceDownload? {
        root.swiftModel.resource.download != nil ? objc_RUMResourceEventResourceDownload(root: root) : nil
    }

    public var duration: NSNumber? {
        root.swiftModel.resource.duration as NSNumber?
    }

    public var encodedBodySize: NSNumber? {
        root.swiftModel.resource.encodedBodySize as NSNumber?
    }

    public var firstByte: objc_RUMResourceEventResourceFirstByte? {
        root.swiftModel.resource.firstByte != nil ? objc_RUMResourceEventResourceFirstByte(root: root) : nil
    }

    public var graphql: objc_RUMResourceEventResourceGraphql? {
        root.swiftModel.resource.graphql != nil ? objc_RUMResourceEventResourceGraphql(root: root) : nil
    }

    public var id: String? {
        root.swiftModel.resource.id
    }

    public var method: objc_RUMResourceEventResourceRUMMethod {
        .init(swift: root.swiftModel.resource.method)
    }

    public var `protocol`: String? {
        root.swiftModel.resource.protocol
    }

    public var provider: objc_RUMResourceEventResourceProvider? {
        root.swiftModel.resource.provider != nil ? objc_RUMResourceEventResourceProvider(root: root) : nil
    }

    public var redirect: objc_RUMResourceEventResourceRedirect? {
        root.swiftModel.resource.redirect != nil ? objc_RUMResourceEventResourceRedirect(root: root) : nil
    }

    public var renderBlockingStatus: objc_RUMResourceEventResourceRenderBlockingStatus {
        .init(swift: root.swiftModel.resource.renderBlockingStatus)
    }

    public var size: NSNumber? {
        root.swiftModel.resource.size as NSNumber?
    }

    public var ssl: objc_RUMResourceEventResourceSSL? {
        root.swiftModel.resource.ssl != nil ? objc_RUMResourceEventResourceSSL(root: root) : nil
    }

    public var statusCode: NSNumber? {
        root.swiftModel.resource.statusCode as NSNumber?
    }

    public var transferSize: NSNumber? {
        root.swiftModel.resource.transferSize as NSNumber?
    }

    public var type: objc_RUMResourceEventResourceResourceType {
        .init(swift: root.swiftModel.resource.type)
    }

    public var url: String {
        set { root.swiftModel.resource.url = newValue }
        get { root.swiftModel.resource.url }
    }

    public var worker: objc_RUMResourceEventResourceWorker? {
        root.swiftModel.resource.worker != nil ? objc_RUMResourceEventResourceWorker(root: root) : nil
    }
}

@objc(DDRUMResourceEventResourceConnect)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceConnect: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.connect!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.connect!.start as NSNumber
    }
}

@objc(DDRUMResourceEventResourceDeliveryType)
@_spi(objc)
public enum objc_RUMResourceEventResourceDeliveryType: Int {
    internal init(swift: RUMResourceEvent.Resource.DeliveryType?) {
        switch swift {
        case nil: self = .none
        case .cache?: self = .cache
        case .navigationalPrefetch?: self = .navigationalPrefetch
        case .other?: self = .other
        }
    }

    internal var toSwift: RUMResourceEvent.Resource.DeliveryType? {
        switch self {
        case .none: return nil
        case .cache: return .cache
        case .navigationalPrefetch: return .navigationalPrefetch
        case .other: return .other
        }
    }

    case none
    case cache
    case navigationalPrefetch
    case other
}

@objc(DDRUMResourceEventResourceDNS)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceDNS: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.dns!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.dns!.start as NSNumber
    }
}

@objc(DDRUMResourceEventResourceDownload)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceDownload: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.download!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.download!.start as NSNumber
    }
}

@objc(DDRUMResourceEventResourceFirstByte)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceFirstByte: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.firstByte!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.firstByte!.start as NSNumber
    }
}

@objc(DDRUMResourceEventResourceGraphql)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceGraphql: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var operationName: String? {
        root.swiftModel.resource.graphql!.operationName
    }

    public var operationType: objc_RUMResourceEventResourceGraphqlOperationType {
        .init(swift: root.swiftModel.resource.graphql!.operationType)
    }

    public var payload: String? {
        set { root.swiftModel.resource.graphql!.payload = newValue }
        get { root.swiftModel.resource.graphql!.payload }
    }

    public var variables: String? {
        set { root.swiftModel.resource.graphql!.variables = newValue }
        get { root.swiftModel.resource.graphql!.variables }
    }
}

@objc(DDRUMResourceEventResourceGraphqlOperationType)
@_spi(objc)
public enum objc_RUMResourceEventResourceGraphqlOperationType: Int {
    internal init(swift: RUMResourceEvent.Resource.Graphql.OperationType) {
        switch swift {
        case .query: self = .query
        case .mutation: self = .mutation
        case .subscription: self = .subscription
        }
    }

    internal var toSwift: RUMResourceEvent.Resource.Graphql.OperationType {
        switch self {
        case .query: return .query
        case .mutation: return .mutation
        case .subscription: return .subscription
        }
    }

    case query
    case mutation
    case subscription
}

@objc(DDRUMResourceEventResourceRUMMethod)
@_spi(objc)
public enum objc_RUMResourceEventResourceRUMMethod: Int {
    internal init(swift: RUMMethod?) {
        switch swift {
        case nil: self = .none
        case .post?: self = .post
        case .get?: self = .get
        case .head?: self = .head
        case .put?: self = .put
        case .delete?: self = .delete
        case .patch?: self = .patch
        case .trace?: self = .trace
        case .options?: self = .options
        case .connect?: self = .connect
        }
    }

    internal var toSwift: RUMMethod? {
        switch self {
        case .none: return nil
        case .post: return .post
        case .get: return .get
        case .head: return .head
        case .put: return .put
        case .delete: return .delete
        case .patch: return .patch
        case .trace: return .trace
        case .options: return .options
        case .connect: return .connect
        }
    }

    case none
    case post
    case get
    case head
    case put
    case delete
    case patch
    case trace
    case options
    case connect
}

@objc(DDRUMResourceEventResourceProvider)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceProvider: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var domain: String? {
        root.swiftModel.resource.provider!.domain
    }

    public var name: String? {
        root.swiftModel.resource.provider!.name
    }

    public var type: objc_RUMResourceEventResourceProviderProviderType {
        .init(swift: root.swiftModel.resource.provider!.type)
    }
}

@objc(DDRUMResourceEventResourceProviderProviderType)
@_spi(objc)
public enum objc_RUMResourceEventResourceProviderProviderType: Int {
    internal init(swift: RUMResourceEvent.Resource.Provider.ProviderType?) {
        switch swift {
        case nil: self = .none
        case .ad?: self = .ad
        case .advertising?: self = .advertising
        case .analytics?: self = .analytics
        case .cdn?: self = .cdn
        case .content?: self = .content
        case .customerSuccess?: self = .customerSuccess
        case .firstParty?: self = .firstParty
        case .hosting?: self = .hosting
        case .marketing?: self = .marketing
        case .other?: self = .other
        case .social?: self = .social
        case .tagManager?: self = .tagManager
        case .utility?: self = .utility
        case .video?: self = .video
        }
    }

    internal var toSwift: RUMResourceEvent.Resource.Provider.ProviderType? {
        switch self {
        case .none: return nil
        case .ad: return .ad
        case .advertising: return .advertising
        case .analytics: return .analytics
        case .cdn: return .cdn
        case .content: return .content
        case .customerSuccess: return .customerSuccess
        case .firstParty: return .firstParty
        case .hosting: return .hosting
        case .marketing: return .marketing
        case .other: return .other
        case .social: return .social
        case .tagManager: return .tagManager
        case .utility: return .utility
        case .video: return .video
        }
    }

    case none
    case ad
    case advertising
    case analytics
    case cdn
    case content
    case customerSuccess
    case firstParty
    case hosting
    case marketing
    case other
    case social
    case tagManager
    case utility
    case video
}

@objc(DDRUMResourceEventResourceRedirect)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceRedirect: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.redirect!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.redirect!.start as NSNumber
    }
}

@objc(DDRUMResourceEventResourceRenderBlockingStatus)
@_spi(objc)
public enum objc_RUMResourceEventResourceRenderBlockingStatus: Int {
    internal init(swift: RUMResourceEvent.Resource.RenderBlockingStatus?) {
        switch swift {
        case nil: self = .none
        case .blocking?: self = .blocking
        case .nonBlocking?: self = .nonBlocking
        }
    }

    internal var toSwift: RUMResourceEvent.Resource.RenderBlockingStatus? {
        switch self {
        case .none: return nil
        case .blocking: return .blocking
        case .nonBlocking: return .nonBlocking
        }
    }

    case none
    case blocking
    case nonBlocking
}

@objc(DDRUMResourceEventResourceSSL)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceSSL: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.ssl!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.ssl!.start as NSNumber
    }
}

@objc(DDRUMResourceEventResourceResourceType)
@_spi(objc)
public enum objc_RUMResourceEventResourceResourceType: Int {
    internal init(swift: RUMResourceEvent.Resource.ResourceType) {
        switch swift {
        case .document: self = .document
        case .xhr: self = .xhr
        case .beacon: self = .beacon
        case .fetch: self = .fetch
        case .css: self = .css
        case .js: self = .js
        case .image: self = .image
        case .font: self = .font
        case .media: self = .media
        case .other: self = .other
        case .native: self = .native
        }
    }

    internal var toSwift: RUMResourceEvent.Resource.ResourceType {
        switch self {
        case .document: return .document
        case .xhr: return .xhr
        case .beacon: return .beacon
        case .fetch: return .fetch
        case .css: return .css
        case .js: return .js
        case .image: return .image
        case .font: return .font
        case .media: return .media
        case .other: return .other
        case .native: return .native
        }
    }

    case document
    case xhr
    case beacon
    case fetch
    case css
    case js
    case image
    case font
    case media
    case other
    case native
}

@objc(DDRUMResourceEventResourceWorker)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventResourceWorker: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.resource.worker!.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.resource.worker!.start as NSNumber
    }
}

@objc(DDRUMResourceEventSession)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventSession: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    public var id: String {
        root.swiftModel.session.id
    }

    public var type: objc_RUMResourceEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc(DDRUMResourceEventSessionRUMSessionType)
@_spi(objc)
public enum objc_RUMResourceEventSessionRUMSessionType: Int {
    internal init(swift: RUMSessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMSessionType {
        switch self {
        case .user: return .user
        case .synthetics: return .synthetics
        case .ciTest: return .ciTest
        }
    }

    case user
    case synthetics
    case ciTest
}

@objc(DDRUMResourceEventSource)
@_spi(objc)
public enum objc_RUMResourceEventSource: Int {
    internal init(swift: RUMResourceEvent.Source?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .ios?: self = .ios
        case .browser?: self = .browser
        case .flutter?: self = .flutter
        case .reactNative?: self = .reactNative
        case .roku?: self = .roku
        case .unity?: self = .unity
        case .kotlinMultiplatform?: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMResourceEvent.Source? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMResourceEventRUMSyntheticsTest)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMSyntheticsTest: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc(DDRUMResourceEventRUMUser)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventRUMUser: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var anonymousId: String? {
        root.swiftModel.usr!.anonymousId
    }

    public var email: String? {
        root.swiftModel.usr!.email
    }

    public var id: String? {
        root.swiftModel.usr!.id
    }

    public var name: String? {
        root.swiftModel.usr!.name
    }

    public var usrInfo: [String: Any] {
        set { root.swiftModel.usr!.usrInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.usr!.usrInfo.dd.objCAttributes }
    }
}

@objc(DDRUMResourceEventView)
@objcMembers
@_spi(objc)
public class objc_RUMResourceEventView: NSObject {
    internal let root: objc_RUMResourceEvent

    internal init(root: objc_RUMResourceEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view.id
    }

    public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc(DDRUMViewEvent)
@objcMembers
@_spi(objc)
public class objc_RUMViewEvent: NSObject {
    public internal(set) var swiftModel: RUMViewEvent
    internal var root: objc_RUMViewEvent { self }

    public init(swiftModel: RUMViewEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_RUMViewEventDD {
        objc_RUMViewEventDD(root: root)
    }

    public var account: objc_RUMViewEventRUMAccount? {
        root.swiftModel.account != nil ? objc_RUMViewEventRUMAccount(root: root) : nil
    }

    public var application: objc_RUMViewEventApplication {
        objc_RUMViewEventApplication(root: root)
    }

    public var buildId: String? {
        root.swiftModel.buildId
    }

    public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    public var ciTest: objc_RUMViewEventRUMCITest? {
        root.swiftModel.ciTest != nil ? objc_RUMViewEventRUMCITest(root: root) : nil
    }

    public var connectivity: objc_RUMViewEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? objc_RUMViewEventRUMConnectivity(root: root) : nil
    }

    public var container: objc_RUMViewEventContainer? {
        root.swiftModel.container != nil ? objc_RUMViewEventContainer(root: root) : nil
    }

    public var context: objc_RUMViewEventRUMEventAttributes? {
        root.swiftModel.context != nil ? objc_RUMViewEventRUMEventAttributes(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var device: objc_RUMViewEventDevice? {
        root.swiftModel.device != nil ? objc_RUMViewEventDevice(root: root) : nil
    }

    public var display: objc_RUMViewEventDisplay? {
        root.swiftModel.display != nil ? objc_RUMViewEventDisplay(root: root) : nil
    }

    public var featureFlags: objc_RUMViewEventFeatureFlags? {
        root.swiftModel.featureFlags != nil ? objc_RUMViewEventFeatureFlags(root: root) : nil
    }

    public var os: objc_RUMViewEventOperatingSystem? {
        root.swiftModel.os != nil ? objc_RUMViewEventOperatingSystem(root: root) : nil
    }

    public var privacy: objc_RUMViewEventPrivacy? {
        root.swiftModel.privacy != nil ? objc_RUMViewEventPrivacy(root: root) : nil
    }

    public var service: String? {
        root.swiftModel.service
    }

    public var session: objc_RUMViewEventSession {
        objc_RUMViewEventSession(root: root)
    }

    public var source: objc_RUMViewEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var synthetics: objc_RUMViewEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? objc_RUMViewEventRUMSyntheticsTest(root: root) : nil
    }

    public var type: String {
        root.swiftModel.type
    }

    public var usr: objc_RUMViewEventRUMUser? {
        root.swiftModel.usr != nil ? objc_RUMViewEventRUMUser(root: root) : nil
    }

    public var version: String? {
        root.swiftModel.version
    }

    public var view: objc_RUMViewEventView {
        objc_RUMViewEventView(root: root)
    }
}

@objc(DDRUMViewEventDD)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDD: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    public var cls: objc_RUMViewEventDDCLS? {
        root.swiftModel.dd.cls != nil ? objc_RUMViewEventDDCLS(root: root) : nil
    }

    public var configuration: objc_RUMViewEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? objc_RUMViewEventDDConfiguration(root: root) : nil
    }

    public var documentVersion: NSNumber {
        root.swiftModel.dd.documentVersion as NSNumber
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    public var pageStates: [objc_RUMViewEventDDPageStates]? {
        root.swiftModel.dd.pageStates?.map { objc_RUMViewEventDDPageStates(swiftModel: $0) }
    }

    public var profiling: objc_RUMViewEventDDProfiling? {
        root.swiftModel.dd.profiling != nil ? objc_RUMViewEventDDProfiling(root: root) : nil
    }

    public var replayStats: objc_RUMViewEventDDReplayStats? {
        root.swiftModel.dd.replayStats != nil ? objc_RUMViewEventDDReplayStats(root: root) : nil
    }

    public var sdkName: String? {
        root.swiftModel.dd.sdkName
    }

    public var session: objc_RUMViewEventDDSession? {
        root.swiftModel.dd.session != nil ? objc_RUMViewEventDDSession(root: root) : nil
    }
}

@objc(DDRUMViewEventDDCLS)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDDCLS: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var devicePixelRatio: NSNumber? {
        root.swiftModel.dd.cls!.devicePixelRatio as NSNumber?
    }
}

@objc(DDRUMViewEventDDConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDDConfiguration: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var profilingSampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.profilingSampleRate as NSNumber?
    }

    public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }

    public var startSessionReplayRecordingManually: NSNumber? {
        root.swiftModel.dd.configuration!.startSessionReplayRecordingManually as NSNumber?
    }
}

@objc(DDRUMViewEventDDPageStates)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDDPageStates: NSObject {
    internal var swiftModel: RUMViewEvent.DD.PageStates
    internal var root: objc_RUMViewEventDDPageStates { self }

    internal init(swiftModel: RUMViewEvent.DD.PageStates) {
        self.swiftModel = swiftModel
    }

    public var start: NSNumber {
        root.swiftModel.start as NSNumber
    }

    public var state: objc_RUMViewEventDDPageStatesState {
        .init(swift: root.swiftModel.state)
    }
}

@objc(DDRUMViewEventDDPageStatesState)
@_spi(objc)
public enum objc_RUMViewEventDDPageStatesState: Int {
    internal init(swift: RUMViewEvent.DD.PageStates.State) {
        switch swift {
        case .active: self = .active
        case .passive: self = .passive
        case .hidden: self = .hidden
        case .frozen: self = .frozen
        case .terminated: self = .terminated
        }
    }

    internal var toSwift: RUMViewEvent.DD.PageStates.State {
        switch self {
        case .active: return .active
        case .passive: return .passive
        case .hidden: return .hidden
        case .frozen: return .frozen
        case .terminated: return .terminated
        }
    }

    case active
    case passive
    case hidden
    case frozen
    case terminated
}

@objc(DDRUMViewEventDDProfiling)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDDProfiling: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var errorReason: objc_RUMViewEventDDProfilingErrorReason {
        .init(swift: root.swiftModel.dd.profiling!.errorReason)
    }

    public var status: objc_RUMViewEventDDProfilingStatus {
        .init(swift: root.swiftModel.dd.profiling!.status)
    }
}

@objc(DDRUMViewEventDDProfilingErrorReason)
@_spi(objc)
public enum objc_RUMViewEventDDProfilingErrorReason: Int {
    internal init(swift: RUMViewEvent.DD.Profiling.ErrorReason?) {
        switch swift {
        case nil: self = .none
        case .notSupportedByBrowser?: self = .notSupportedByBrowser
        case .failedToLazyLoad?: self = .failedToLazyLoad
        case .missingDocumentPolicyHeader?: self = .missingDocumentPolicyHeader
        case .unexpectedException?: self = .unexpectedException
        }
    }

    internal var toSwift: RUMViewEvent.DD.Profiling.ErrorReason? {
        switch self {
        case .none: return nil
        case .notSupportedByBrowser: return .notSupportedByBrowser
        case .failedToLazyLoad: return .failedToLazyLoad
        case .missingDocumentPolicyHeader: return .missingDocumentPolicyHeader
        case .unexpectedException: return .unexpectedException
        }
    }

    case none
    case notSupportedByBrowser
    case failedToLazyLoad
    case missingDocumentPolicyHeader
    case unexpectedException
}

@objc(DDRUMViewEventDDProfilingStatus)
@_spi(objc)
public enum objc_RUMViewEventDDProfilingStatus: Int {
    internal init(swift: RUMViewEvent.DD.Profiling.Status?) {
        switch swift {
        case nil: self = .none
        case .starting?: self = .starting
        case .running?: self = .running
        case .stopped?: self = .stopped
        case .error?: self = .error
        }
    }

    internal var toSwift: RUMViewEvent.DD.Profiling.Status? {
        switch self {
        case .none: return nil
        case .starting: return .starting
        case .running: return .running
        case .stopped: return .stopped
        case .error: return .error
        }
    }

    case none
    case starting
    case running
    case stopped
    case error
}

@objc(DDRUMViewEventDDReplayStats)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDDReplayStats: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var recordsCount: NSNumber? {
        root.swiftModel.dd.replayStats!.recordsCount as NSNumber?
    }

    public var segmentsCount: NSNumber? {
        root.swiftModel.dd.replayStats!.segmentsCount as NSNumber?
    }

    public var segmentsTotalRawSize: NSNumber? {
        root.swiftModel.dd.replayStats!.segmentsTotalRawSize as NSNumber?
    }
}

@objc(DDRUMViewEventDDSession)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDDSession: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var plan: objc_RUMViewEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    public var sessionPrecondition: objc_RUMViewEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc(DDRUMViewEventDDSessionPlan)
@_spi(objc)
public enum objc_RUMViewEventDDSessionPlan: Int {
    internal init(swift: RUMViewEvent.DD.Session.Plan?) {
        switch swift {
        case nil: self = .none
        case .plan1?: self = .plan1
        case .plan2?: self = .plan2
        }
    }

    internal var toSwift: RUMViewEvent.DD.Session.Plan? {
        switch self {
        case .none: return nil
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case none
    case plan1
    case plan2
}

@objc(DDRUMViewEventDDSessionRUMSessionPrecondition)
@_spi(objc)
public enum objc_RUMViewEventDDSessionRUMSessionPrecondition: Int {
    internal init(swift: RUMSessionPrecondition?) {
        switch swift {
        case nil: self = .none
        case .userAppLaunch?: self = .userAppLaunch
        case .inactivityTimeout?: self = .inactivityTimeout
        case .maxDuration?: self = .maxDuration
        case .backgroundLaunch?: self = .backgroundLaunch
        case .prewarm?: self = .prewarm
        case .fromNonInteractiveSession?: self = .fromNonInteractiveSession
        case .explicitStop?: self = .explicitStop
        }
    }

    internal var toSwift: RUMSessionPrecondition? {
        switch self {
        case .none: return nil
        case .userAppLaunch: return .userAppLaunch
        case .inactivityTimeout: return .inactivityTimeout
        case .maxDuration: return .maxDuration
        case .backgroundLaunch: return .backgroundLaunch
        case .prewarm: return .prewarm
        case .fromNonInteractiveSession: return .fromNonInteractiveSession
        case .explicitStop: return .explicitStop
        }
    }

    case none
    case userAppLaunch
    case inactivityTimeout
    case maxDuration
    case backgroundLaunch
    case prewarm
    case fromNonInteractiveSession
    case explicitStop
}

@objc(DDRUMViewEventRUMAccount)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMAccount: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.account!.id
    }

    public var name: String? {
        root.swiftModel.account!.name
    }

    public var accountInfo: [String: Any] {
        set { root.swiftModel.account!.accountInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.account!.accountInfo.dd.objCAttributes }
    }
}

@objc(DDRUMViewEventApplication)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventApplication: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var currentLocale: String? {
        root.swiftModel.application.currentLocale
    }

    public var id: String {
        root.swiftModel.application.id
    }
}

@objc(DDRUMViewEventRUMCITest)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMCITest: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc(DDRUMViewEventRUMConnectivity)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMConnectivity: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var cellular: objc_RUMViewEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? objc_RUMViewEventRUMConnectivityCellular(root: root) : nil
    }

    public var effectiveType: objc_RUMViewEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { objc_RUMViewEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    public var status: objc_RUMViewEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc(DDRUMViewEventRUMConnectivityCellular)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMConnectivityCellular: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc(DDRUMViewEventRUMConnectivityEffectiveType)
@_spi(objc)
public enum objc_RUMViewEventRUMConnectivityEffectiveType: Int {
    internal init(swift: RUMConnectivity.EffectiveType?) {
        switch swift {
        case nil: self = .none
        case .slow2g?: self = .slow2g
        case .effectiveType2g?: self = .effectiveType2g
        case .effectiveType3g?: self = .effectiveType3g
        case .effectiveType4g?: self = .effectiveType4g
        }
    }

    internal var toSwift: RUMConnectivity.EffectiveType? {
        switch self {
        case .none: return nil
        case .slow2g: return .slow2g
        case .effectiveType2g: return .effectiveType2g
        case .effectiveType3g: return .effectiveType3g
        case .effectiveType4g: return .effectiveType4g
        }
    }

    case none
    case slow2g
    case effectiveType2g
    case effectiveType3g
    case effectiveType4g
}

@objc(DDRUMViewEventRUMConnectivityInterfaces)
@_spi(objc)
public enum objc_RUMViewEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces?) {
        switch swift {
        case nil: self = .none
        case .bluetooth?: self = .bluetooth
        case .cellular?: self = .cellular
        case .ethernet?: self = .ethernet
        case .wifi?: self = .wifi
        case .wimax?: self = .wimax
        case .mixed?: self = .mixed
        case .other?: self = .other
        case .unknown?: self = .unknown
        case .interfacesNone?: self = .interfacesNone
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces? {
        switch self {
        case .none: return nil
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .interfacesNone: return .interfacesNone
        }
    }

    case none
    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case interfacesNone
}

@objc(DDRUMViewEventRUMConnectivityStatus)
@_spi(objc)
public enum objc_RUMViewEventRUMConnectivityStatus: Int {
    internal init(swift: RUMConnectivity.Status) {
        switch swift {
        case .connected: self = .connected
        case .notConnected: self = .notConnected
        case .maybe: self = .maybe
        }
    }

    internal var toSwift: RUMConnectivity.Status {
        switch self {
        case .connected: return .connected
        case .notConnected: return .notConnected
        case .maybe: return .maybe
        }
    }

    case connected
    case notConnected
    case maybe
}

@objc(DDRUMViewEventContainer)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventContainer: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var source: objc_RUMViewEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    public var view: objc_RUMViewEventContainerView {
        objc_RUMViewEventContainerView(root: root)
    }
}

@objc(DDRUMViewEventContainerSource)
@_spi(objc)
public enum objc_RUMViewEventContainerSource: Int {
    internal init(swift: RUMViewEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMViewEvent.Container.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMViewEventContainerView)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventContainerView: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc(DDRUMViewEventRUMEventAttributes)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMEventAttributes: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var contextInfo: [String: Any] {
        set { root.swiftModel.context!.contextInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.context!.contextInfo.dd.objCAttributes }
    }
}

@objc(DDRUMViewEventDevice)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDevice: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    public var batteryLevel: NSNumber? {
        root.swiftModel.device!.batteryLevel as NSNumber?
    }

    public var brand: String? {
        root.swiftModel.device!.brand
    }

    public var brightnessLevel: NSNumber? {
        root.swiftModel.device!.brightnessLevel as NSNumber?
    }

    public var locale: String? {
        root.swiftModel.device!.locale
    }

    public var locales: [String]? {
        root.swiftModel.device!.locales
    }

    public var model: String? {
        root.swiftModel.device!.model
    }

    public var name: String? {
        root.swiftModel.device!.name
    }

    public var powerSavingMode: NSNumber? {
        root.swiftModel.device!.powerSavingMode as NSNumber?
    }

    public var timeZone: String? {
        root.swiftModel.device!.timeZone
    }

    public var type: objc_RUMViewEventDeviceDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc(DDRUMViewEventDeviceDeviceType)
@_spi(objc)
public enum objc_RUMViewEventDeviceDeviceType: Int {
    internal init(swift: Device.DeviceType?) {
        switch swift {
        case nil: self = .none
        case .mobile?: self = .mobile
        case .desktop?: self = .desktop
        case .tablet?: self = .tablet
        case .tv?: self = .tv
        case .gamingConsole?: self = .gamingConsole
        case .bot?: self = .bot
        case .other?: self = .other
        }
    }

    internal var toSwift: Device.DeviceType? {
        switch self {
        case .none: return nil
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case none
    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc(DDRUMViewEventDisplay)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDisplay: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var scroll: objc_RUMViewEventDisplayScroll? {
        root.swiftModel.display!.scroll != nil ? objc_RUMViewEventDisplayScroll(root: root) : nil
    }

    public var viewport: objc_RUMViewEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? objc_RUMViewEventDisplayViewport(root: root) : nil
    }
}

@objc(DDRUMViewEventDisplayScroll)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDisplayScroll: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var maxDepth: NSNumber {
        root.swiftModel.display!.scroll!.maxDepth as NSNumber
    }

    public var maxDepthScrollTop: NSNumber {
        root.swiftModel.display!.scroll!.maxDepthScrollTop as NSNumber
    }

    public var maxScrollHeight: NSNumber {
        root.swiftModel.display!.scroll!.maxScrollHeight as NSNumber
    }

    public var maxScrollHeightTime: NSNumber {
        root.swiftModel.display!.scroll!.maxScrollHeightTime as NSNumber
    }
}

@objc(DDRUMViewEventDisplayViewport)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventDisplayViewport: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc(DDRUMViewEventFeatureFlags)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventFeatureFlags: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var featureFlagsInfo: [String: Any] {
        set { root.swiftModel.featureFlags!.featureFlagsInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.featureFlags!.featureFlagsInfo.dd.objCAttributes }
    }
}

@objc(DDRUMViewEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventOperatingSystem: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.os!.build
    }

    public var name: String {
        root.swiftModel.os!.name
    }

    public var version: String {
        root.swiftModel.os!.version
    }

    public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc(DDRUMViewEventPrivacy)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventPrivacy: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var replayLevel: objc_RUMViewEventPrivacyReplayLevel {
        .init(swift: root.swiftModel.privacy!.replayLevel)
    }
}

@objc(DDRUMViewEventPrivacyReplayLevel)
@_spi(objc)
public enum objc_RUMViewEventPrivacyReplayLevel: Int {
    internal init(swift: RUMViewEvent.Privacy.ReplayLevel) {
        switch swift {
        case .allow: self = .allow
        case .mask: self = .mask
        case .maskUserInput: self = .maskUserInput
        }
    }

    internal var toSwift: RUMViewEvent.Privacy.ReplayLevel {
        switch self {
        case .allow: return .allow
        case .mask: return .mask
        case .maskUserInput: return .maskUserInput
        }
    }

    case allow
    case mask
    case maskUserInput
}

@objc(DDRUMViewEventSession)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventSession: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    public var id: String {
        root.swiftModel.session.id
    }

    public var isActive: NSNumber? {
        root.swiftModel.session.isActive as NSNumber?
    }

    public var sampledForReplay: NSNumber? {
        root.swiftModel.session.sampledForReplay as NSNumber?
    }

    public var type: objc_RUMViewEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc(DDRUMViewEventSessionRUMSessionType)
@_spi(objc)
public enum objc_RUMViewEventSessionRUMSessionType: Int {
    internal init(swift: RUMSessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMSessionType {
        switch self {
        case .user: return .user
        case .synthetics: return .synthetics
        case .ciTest: return .ciTest
        }
    }

    case user
    case synthetics
    case ciTest
}

@objc(DDRUMViewEventSource)
@_spi(objc)
public enum objc_RUMViewEventSource: Int {
    internal init(swift: RUMViewEvent.Source?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .ios?: self = .ios
        case .browser?: self = .browser
        case .flutter?: self = .flutter
        case .reactNative?: self = .reactNative
        case .roku?: self = .roku
        case .unity?: self = .unity
        case .kotlinMultiplatform?: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMViewEvent.Source? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMViewEventRUMSyntheticsTest)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMSyntheticsTest: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc(DDRUMViewEventRUMUser)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventRUMUser: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var anonymousId: String? {
        root.swiftModel.usr!.anonymousId
    }

    public var email: String? {
        root.swiftModel.usr!.email
    }

    public var id: String? {
        root.swiftModel.usr!.id
    }

    public var name: String? {
        root.swiftModel.usr!.name
    }

    public var usrInfo: [String: Any] {
        set { root.swiftModel.usr!.usrInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.usr!.usrInfo.dd.objCAttributes }
    }
}

@objc(DDRUMViewEventView)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventView: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var action: objc_RUMViewEventViewAction {
        objc_RUMViewEventViewAction(root: root)
    }

    public var cpuTicksCount: NSNumber? {
        root.swiftModel.view.cpuTicksCount as NSNumber?
    }

    public var cpuTicksPerSecond: NSNumber? {
        root.swiftModel.view.cpuTicksPerSecond as NSNumber?
    }

    public var crash: objc_RUMViewEventViewCrash? {
        root.swiftModel.view.crash != nil ? objc_RUMViewEventViewCrash(root: root) : nil
    }

    public var cumulativeLayoutShift: NSNumber? {
        root.swiftModel.view.cumulativeLayoutShift as NSNumber?
    }

    public var cumulativeLayoutShiftTargetSelector: String? {
        root.swiftModel.view.cumulativeLayoutShiftTargetSelector
    }

    public var cumulativeLayoutShiftTime: NSNumber? {
        root.swiftModel.view.cumulativeLayoutShiftTime as NSNumber?
    }

    public var customTimings: [String: NSNumber]? {
        root.swiftModel.view.customTimings as [String: NSNumber]?
    }

    public var domComplete: NSNumber? {
        root.swiftModel.view.domComplete as NSNumber?
    }

    public var domContentLoaded: NSNumber? {
        root.swiftModel.view.domContentLoaded as NSNumber?
    }

    public var domInteractive: NSNumber? {
        root.swiftModel.view.domInteractive as NSNumber?
    }

    public var error: objc_RUMViewEventViewError {
        objc_RUMViewEventViewError(root: root)
    }

    public var firstByte: NSNumber? {
        root.swiftModel.view.firstByte as NSNumber?
    }

    public var firstContentfulPaint: NSNumber? {
        root.swiftModel.view.firstContentfulPaint as NSNumber?
    }

    public var firstInputDelay: NSNumber? {
        root.swiftModel.view.firstInputDelay as NSNumber?
    }

    public var firstInputTargetSelector: String? {
        root.swiftModel.view.firstInputTargetSelector
    }

    public var firstInputTime: NSNumber? {
        root.swiftModel.view.firstInputTime as NSNumber?
    }

    public var flutterBuildTime: objc_RUMViewEventViewFlutterBuildTime? {
        root.swiftModel.view.flutterBuildTime != nil ? objc_RUMViewEventViewFlutterBuildTime(root: root) : nil
    }

    public var flutterRasterTime: objc_RUMViewEventViewFlutterRasterTime? {
        root.swiftModel.view.flutterRasterTime != nil ? objc_RUMViewEventViewFlutterRasterTime(root: root) : nil
    }

    public var freezeRate: NSNumber? {
        root.swiftModel.view.freezeRate as NSNumber?
    }

    public var frozenFrame: objc_RUMViewEventViewFrozenFrame? {
        root.swiftModel.view.frozenFrame != nil ? objc_RUMViewEventViewFrozenFrame(root: root) : nil
    }

    public var frustration: objc_RUMViewEventViewFrustration? {
        root.swiftModel.view.frustration != nil ? objc_RUMViewEventViewFrustration(root: root) : nil
    }

    public var id: String {
        root.swiftModel.view.id
    }

    public var inForegroundPeriods: [objc_RUMViewEventViewInForegroundPeriods]? {
        root.swiftModel.view.inForegroundPeriods?.map { objc_RUMViewEventViewInForegroundPeriods(swiftModel: $0) }
    }

    public var interactionToNextPaint: NSNumber? {
        root.swiftModel.view.interactionToNextPaint as NSNumber?
    }

    public var interactionToNextPaintTargetSelector: String? {
        root.swiftModel.view.interactionToNextPaintTargetSelector
    }

    public var interactionToNextPaintTime: NSNumber? {
        root.swiftModel.view.interactionToNextPaintTime as NSNumber?
    }

    public var interactionToNextViewTime: NSNumber? {
        root.swiftModel.view.interactionToNextViewTime as NSNumber?
    }

    public var isActive: NSNumber? {
        root.swiftModel.view.isActive as NSNumber?
    }

    public var isSlowRendered: NSNumber? {
        root.swiftModel.view.isSlowRendered as NSNumber?
    }

    public var jsRefreshRate: objc_RUMViewEventViewJsRefreshRate? {
        root.swiftModel.view.jsRefreshRate != nil ? objc_RUMViewEventViewJsRefreshRate(root: root) : nil
    }

    public var largestContentfulPaint: NSNumber? {
        root.swiftModel.view.largestContentfulPaint as NSNumber?
    }

    public var largestContentfulPaintTargetSelector: String? {
        root.swiftModel.view.largestContentfulPaintTargetSelector
    }

    public var loadEvent: NSNumber? {
        root.swiftModel.view.loadEvent as NSNumber?
    }

    public var loadingTime: NSNumber? {
        root.swiftModel.view.loadingTime as NSNumber?
    }

    public var loadingType: objc_RUMViewEventViewLoadingType {
        .init(swift: root.swiftModel.view.loadingType)
    }

    public var longTask: objc_RUMViewEventViewLongTask? {
        root.swiftModel.view.longTask != nil ? objc_RUMViewEventViewLongTask(root: root) : nil
    }

    public var memoryAverage: NSNumber? {
        root.swiftModel.view.memoryAverage as NSNumber?
    }

    public var memoryMax: NSNumber? {
        root.swiftModel.view.memoryMax as NSNumber?
    }

    public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    public var networkSettledTime: NSNumber? {
        root.swiftModel.view.networkSettledTime as NSNumber?
    }

    public var performance: objc_RUMViewEventViewPerformance? {
        root.swiftModel.view.performance != nil ? objc_RUMViewEventViewPerformance(root: root) : nil
    }

    public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    public var refreshRateAverage: NSNumber? {
        root.swiftModel.view.refreshRateAverage as NSNumber?
    }

    public var refreshRateMin: NSNumber? {
        root.swiftModel.view.refreshRateMin as NSNumber?
    }

    public var resource: objc_RUMViewEventViewResource {
        objc_RUMViewEventViewResource(root: root)
    }

    public var slowFrames: [objc_RUMViewEventViewSlowFrames]? {
        root.swiftModel.view.slowFrames?.map { objc_RUMViewEventViewSlowFrames(swiftModel: $0) }
    }

    public var slowFramesRate: NSNumber? {
        root.swiftModel.view.slowFramesRate as NSNumber?
    }

    public var timeSpent: NSNumber {
        root.swiftModel.view.timeSpent as NSNumber
    }

    public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc(DDRUMViewEventViewAction)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewAction: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.action.count as NSNumber
    }
}

@objc(DDRUMViewEventViewCrash)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewCrash: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.crash!.count as NSNumber
    }
}

@objc(DDRUMViewEventViewError)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewError: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.error.count as NSNumber
    }
}

@objc(DDRUMViewEventViewFlutterBuildTime)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewFlutterBuildTime: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var average: NSNumber {
        root.swiftModel.view.flutterBuildTime!.average as NSNumber
    }

    public var max: NSNumber {
        root.swiftModel.view.flutterBuildTime!.max as NSNumber
    }

    public var metricMax: NSNumber? {
        root.swiftModel.view.flutterBuildTime!.metricMax as NSNumber?
    }

    public var min: NSNumber {
        root.swiftModel.view.flutterBuildTime!.min as NSNumber
    }
}

@objc(DDRUMViewEventViewFlutterRasterTime)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewFlutterRasterTime: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var average: NSNumber {
        root.swiftModel.view.flutterRasterTime!.average as NSNumber
    }

    public var max: NSNumber {
        root.swiftModel.view.flutterRasterTime!.max as NSNumber
    }

    public var metricMax: NSNumber? {
        root.swiftModel.view.flutterRasterTime!.metricMax as NSNumber?
    }

    public var min: NSNumber {
        root.swiftModel.view.flutterRasterTime!.min as NSNumber
    }
}

@objc(DDRUMViewEventViewFrozenFrame)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewFrozenFrame: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.frozenFrame!.count as NSNumber
    }
}

@objc(DDRUMViewEventViewFrustration)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewFrustration: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.frustration!.count as NSNumber
    }
}

@objc(DDRUMViewEventViewInForegroundPeriods)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewInForegroundPeriods: NSObject {
    internal var swiftModel: RUMViewEvent.View.InForegroundPeriods
    internal var root: objc_RUMViewEventViewInForegroundPeriods { self }

    internal init(swiftModel: RUMViewEvent.View.InForegroundPeriods) {
        self.swiftModel = swiftModel
    }

    public var duration: NSNumber {
        root.swiftModel.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.start as NSNumber
    }
}

@objc(DDRUMViewEventViewJsRefreshRate)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewJsRefreshRate: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var average: NSNumber {
        root.swiftModel.view.jsRefreshRate!.average as NSNumber
    }

    public var max: NSNumber {
        root.swiftModel.view.jsRefreshRate!.max as NSNumber
    }

    public var metricMax: NSNumber? {
        root.swiftModel.view.jsRefreshRate!.metricMax as NSNumber?
    }

    public var min: NSNumber {
        root.swiftModel.view.jsRefreshRate!.min as NSNumber
    }
}

@objc(DDRUMViewEventViewLoadingType)
@_spi(objc)
public enum objc_RUMViewEventViewLoadingType: Int {
    internal init(swift: RUMViewEvent.View.LoadingType?) {
        switch swift {
        case nil: self = .none
        case .initialLoad?: self = .initialLoad
        case .routeChange?: self = .routeChange
        case .activityDisplay?: self = .activityDisplay
        case .activityRedisplay?: self = .activityRedisplay
        case .fragmentDisplay?: self = .fragmentDisplay
        case .fragmentRedisplay?: self = .fragmentRedisplay
        case .viewControllerDisplay?: self = .viewControllerDisplay
        case .viewControllerRedisplay?: self = .viewControllerRedisplay
        }
    }

    internal var toSwift: RUMViewEvent.View.LoadingType? {
        switch self {
        case .none: return nil
        case .initialLoad: return .initialLoad
        case .routeChange: return .routeChange
        case .activityDisplay: return .activityDisplay
        case .activityRedisplay: return .activityRedisplay
        case .fragmentDisplay: return .fragmentDisplay
        case .fragmentRedisplay: return .fragmentRedisplay
        case .viewControllerDisplay: return .viewControllerDisplay
        case .viewControllerRedisplay: return .viewControllerRedisplay
        }
    }

    case none
    case initialLoad
    case routeChange
    case activityDisplay
    case activityRedisplay
    case fragmentDisplay
    case fragmentRedisplay
    case viewControllerDisplay
    case viewControllerRedisplay
}

@objc(DDRUMViewEventViewLongTask)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewLongTask: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.longTask!.count as NSNumber
    }
}

@objc(DDRUMViewEventViewPerformance)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformance: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var cls: objc_RUMViewEventViewPerformanceCLS? {
        root.swiftModel.view.performance!.cls != nil ? objc_RUMViewEventViewPerformanceCLS(root: root) : nil
    }

    public var fbc: objc_RUMViewEventViewPerformanceFBC? {
        root.swiftModel.view.performance!.fbc != nil ? objc_RUMViewEventViewPerformanceFBC(root: root) : nil
    }

    public var fcp: objc_RUMViewEventViewPerformanceFCP? {
        root.swiftModel.view.performance!.fcp != nil ? objc_RUMViewEventViewPerformanceFCP(root: root) : nil
    }

    public var fid: objc_RUMViewEventViewPerformanceFID? {
        root.swiftModel.view.performance!.fid != nil ? objc_RUMViewEventViewPerformanceFID(root: root) : nil
    }

    public var inp: objc_RUMViewEventViewPerformanceINP? {
        root.swiftModel.view.performance!.inp != nil ? objc_RUMViewEventViewPerformanceINP(root: root) : nil
    }

    public var lcp: objc_RUMViewEventViewPerformanceLCP? {
        root.swiftModel.view.performance!.lcp != nil ? objc_RUMViewEventViewPerformanceLCP(root: root) : nil
    }
}

@objc(DDRUMViewEventViewPerformanceCLS)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceCLS: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var currentRect: objc_RUMViewEventViewPerformanceCLSCurrentRect? {
        root.swiftModel.view.performance!.cls!.currentRect != nil ? objc_RUMViewEventViewPerformanceCLSCurrentRect(root: root) : nil
    }

    public var previousRect: objc_RUMViewEventViewPerformanceCLSPreviousRect? {
        root.swiftModel.view.performance!.cls!.previousRect != nil ? objc_RUMViewEventViewPerformanceCLSPreviousRect(root: root) : nil
    }

    public var score: NSNumber {
        root.swiftModel.view.performance!.cls!.score as NSNumber
    }

    public var targetSelector: String? {
        root.swiftModel.view.performance!.cls!.targetSelector
    }

    public var timestamp: NSNumber? {
        root.swiftModel.view.performance!.cls!.timestamp as NSNumber?
    }
}

@objc(DDRUMViewEventViewPerformanceCLSCurrentRect)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceCLSCurrentRect: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.view.performance!.cls!.currentRect!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.view.performance!.cls!.currentRect!.width as NSNumber
    }

    public var x: NSNumber {
        root.swiftModel.view.performance!.cls!.currentRect!.x as NSNumber
    }

    public var y: NSNumber {
        root.swiftModel.view.performance!.cls!.currentRect!.y as NSNumber
    }
}

@objc(DDRUMViewEventViewPerformanceCLSPreviousRect)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceCLSPreviousRect: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.view.performance!.cls!.previousRect!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.view.performance!.cls!.previousRect!.width as NSNumber
    }

    public var x: NSNumber {
        root.swiftModel.view.performance!.cls!.previousRect!.x as NSNumber
    }

    public var y: NSNumber {
        root.swiftModel.view.performance!.cls!.previousRect!.y as NSNumber
    }
}

@objc(DDRUMViewEventViewPerformanceFBC)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceFBC: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var timestamp: NSNumber {
        root.swiftModel.view.performance!.fbc!.timestamp as NSNumber
    }
}

@objc(DDRUMViewEventViewPerformanceFCP)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceFCP: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var timestamp: NSNumber {
        root.swiftModel.view.performance!.fcp!.timestamp as NSNumber
    }
}

@objc(DDRUMViewEventViewPerformanceFID)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceFID: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.view.performance!.fid!.duration as NSNumber
    }

    public var targetSelector: String? {
        root.swiftModel.view.performance!.fid!.targetSelector
    }

    public var timestamp: NSNumber {
        root.swiftModel.view.performance!.fid!.timestamp as NSNumber
    }
}

@objc(DDRUMViewEventViewPerformanceINP)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceINP: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var duration: NSNumber {
        root.swiftModel.view.performance!.inp!.duration as NSNumber
    }

    public var targetSelector: String? {
        root.swiftModel.view.performance!.inp!.targetSelector
    }

    public var timestamp: NSNumber? {
        root.swiftModel.view.performance!.inp!.timestamp as NSNumber?
    }
}

@objc(DDRUMViewEventViewPerformanceLCP)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewPerformanceLCP: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var resourceUrl: String? {
        set { root.swiftModel.view.performance!.lcp!.resourceUrl = newValue }
        get { root.swiftModel.view.performance!.lcp!.resourceUrl }
    }

    public var targetSelector: String? {
        root.swiftModel.view.performance!.lcp!.targetSelector
    }

    public var timestamp: NSNumber {
        root.swiftModel.view.performance!.lcp!.timestamp as NSNumber
    }
}

@objc(DDRUMViewEventViewResource)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewResource: NSObject {
    internal let root: objc_RUMViewEvent

    internal init(root: objc_RUMViewEvent) {
        self.root = root
    }

    public var count: NSNumber {
        root.swiftModel.view.resource.count as NSNumber
    }
}

@objc(DDRUMViewEventViewSlowFrames)
@objcMembers
@_spi(objc)
public class objc_RUMViewEventViewSlowFrames: NSObject {
    internal var swiftModel: RUMViewEvent.View.SlowFrames
    internal var root: objc_RUMViewEventViewSlowFrames { self }

    internal init(swiftModel: RUMViewEvent.View.SlowFrames) {
        self.swiftModel = swiftModel
    }

    public var duration: NSNumber {
        root.swiftModel.duration as NSNumber
    }

    public var start: NSNumber {
        root.swiftModel.start as NSNumber
    }
}

@objc(DDRUMVitalEvent)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEvent: NSObject {
    public internal(set) var swiftModel: RUMVitalEvent
    internal var root: objc_RUMVitalEvent { self }

    public init(swiftModel: RUMVitalEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_RUMVitalEventDD {
        objc_RUMVitalEventDD(root: root)
    }

    public var account: objc_RUMVitalEventRUMAccount? {
        root.swiftModel.account != nil ? objc_RUMVitalEventRUMAccount(root: root) : nil
    }

    public var application: objc_RUMVitalEventApplication {
        objc_RUMVitalEventApplication(root: root)
    }

    public var buildId: String? {
        root.swiftModel.buildId
    }

    public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    public var ciTest: objc_RUMVitalEventRUMCITest? {
        root.swiftModel.ciTest != nil ? objc_RUMVitalEventRUMCITest(root: root) : nil
    }

    public var connectivity: objc_RUMVitalEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? objc_RUMVitalEventRUMConnectivity(root: root) : nil
    }

    public var container: objc_RUMVitalEventContainer? {
        root.swiftModel.container != nil ? objc_RUMVitalEventContainer(root: root) : nil
    }

    public var context: objc_RUMVitalEventRUMEventAttributes? {
        root.swiftModel.context != nil ? objc_RUMVitalEventRUMEventAttributes(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var device: objc_RUMVitalEventDevice? {
        root.swiftModel.device != nil ? objc_RUMVitalEventDevice(root: root) : nil
    }

    public var display: objc_RUMVitalEventDisplay? {
        root.swiftModel.display != nil ? objc_RUMVitalEventDisplay(root: root) : nil
    }

    public var os: objc_RUMVitalEventOperatingSystem? {
        root.swiftModel.os != nil ? objc_RUMVitalEventOperatingSystem(root: root) : nil
    }

    public var service: String? {
        root.swiftModel.service
    }

    public var session: objc_RUMVitalEventSession {
        objc_RUMVitalEventSession(root: root)
    }

    public var source: objc_RUMVitalEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var synthetics: objc_RUMVitalEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? objc_RUMVitalEventRUMSyntheticsTest(root: root) : nil
    }

    public var type: String {
        root.swiftModel.type
    }

    public var usr: objc_RUMVitalEventRUMUser? {
        root.swiftModel.usr != nil ? objc_RUMVitalEventRUMUser(root: root) : nil
    }

    public var version: String? {
        root.swiftModel.version
    }

    public var view: objc_RUMVitalEventView {
        objc_RUMVitalEventView(root: root)
    }

    public var vital: objc_RUMVitalEventVital {
        objc_RUMVitalEventVital(root: root)
    }
}

@objc(DDRUMVitalEventDD)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDD: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    public var configuration: objc_RUMVitalEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? objc_RUMVitalEventDDConfiguration(root: root) : nil
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    public var sdkName: String? {
        root.swiftModel.dd.sdkName
    }

    public var session: objc_RUMVitalEventDDSession? {
        root.swiftModel.dd.session != nil ? objc_RUMVitalEventDDSession(root: root) : nil
    }

    public var vital: objc_RUMVitalEventDDVital? {
        root.swiftModel.dd.vital != nil ? objc_RUMVitalEventDDVital(root: root) : nil
    }
}

@objc(DDRUMVitalEventDDConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDDConfiguration: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var profilingSampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.profilingSampleRate as NSNumber?
    }

    public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc(DDRUMVitalEventDDSession)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDDSession: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var plan: objc_RUMVitalEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    public var sessionPrecondition: objc_RUMVitalEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc(DDRUMVitalEventDDSessionPlan)
@_spi(objc)
public enum objc_RUMVitalEventDDSessionPlan: Int {
    internal init(swift: RUMVitalEvent.DD.Session.Plan?) {
        switch swift {
        case nil: self = .none
        case .plan1?: self = .plan1
        case .plan2?: self = .plan2
        }
    }

    internal var toSwift: RUMVitalEvent.DD.Session.Plan? {
        switch self {
        case .none: return nil
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case none
    case plan1
    case plan2
}

@objc(DDRUMVitalEventDDSessionRUMSessionPrecondition)
@_spi(objc)
public enum objc_RUMVitalEventDDSessionRUMSessionPrecondition: Int {
    internal init(swift: RUMSessionPrecondition?) {
        switch swift {
        case nil: self = .none
        case .userAppLaunch?: self = .userAppLaunch
        case .inactivityTimeout?: self = .inactivityTimeout
        case .maxDuration?: self = .maxDuration
        case .backgroundLaunch?: self = .backgroundLaunch
        case .prewarm?: self = .prewarm
        case .fromNonInteractiveSession?: self = .fromNonInteractiveSession
        case .explicitStop?: self = .explicitStop
        }
    }

    internal var toSwift: RUMSessionPrecondition? {
        switch self {
        case .none: return nil
        case .userAppLaunch: return .userAppLaunch
        case .inactivityTimeout: return .inactivityTimeout
        case .maxDuration: return .maxDuration
        case .backgroundLaunch: return .backgroundLaunch
        case .prewarm: return .prewarm
        case .fromNonInteractiveSession: return .fromNonInteractiveSession
        case .explicitStop: return .explicitStop
        }
    }

    case none
    case userAppLaunch
    case inactivityTimeout
    case maxDuration
    case backgroundLaunch
    case prewarm
    case fromNonInteractiveSession
    case explicitStop
}

@objc(DDRUMVitalEventDDVital)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDDVital: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var computedValue: NSNumber? {
        root.swiftModel.dd.vital!.computedValue as NSNumber?
    }
}

@objc(DDRUMVitalEventRUMAccount)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMAccount: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.account!.id
    }

    public var name: String? {
        root.swiftModel.account!.name
    }

    public var accountInfo: [String: Any] {
        set { root.swiftModel.account!.accountInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.account!.accountInfo.dd.objCAttributes }
    }
}

@objc(DDRUMVitalEventApplication)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventApplication: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var currentLocale: String? {
        root.swiftModel.application.currentLocale
    }

    public var id: String {
        root.swiftModel.application.id
    }
}

@objc(DDRUMVitalEventRUMCITest)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMCITest: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc(DDRUMVitalEventRUMConnectivity)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMConnectivity: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var cellular: objc_RUMVitalEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? objc_RUMVitalEventRUMConnectivityCellular(root: root) : nil
    }

    public var effectiveType: objc_RUMVitalEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { objc_RUMVitalEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    public var status: objc_RUMVitalEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc(DDRUMVitalEventRUMConnectivityCellular)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMConnectivityCellular: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc(DDRUMVitalEventRUMConnectivityEffectiveType)
@_spi(objc)
public enum objc_RUMVitalEventRUMConnectivityEffectiveType: Int {
    internal init(swift: RUMConnectivity.EffectiveType?) {
        switch swift {
        case nil: self = .none
        case .slow2g?: self = .slow2g
        case .effectiveType2g?: self = .effectiveType2g
        case .effectiveType3g?: self = .effectiveType3g
        case .effectiveType4g?: self = .effectiveType4g
        }
    }

    internal var toSwift: RUMConnectivity.EffectiveType? {
        switch self {
        case .none: return nil
        case .slow2g: return .slow2g
        case .effectiveType2g: return .effectiveType2g
        case .effectiveType3g: return .effectiveType3g
        case .effectiveType4g: return .effectiveType4g
        }
    }

    case none
    case slow2g
    case effectiveType2g
    case effectiveType3g
    case effectiveType4g
}

@objc(DDRUMVitalEventRUMConnectivityInterfaces)
@_spi(objc)
public enum objc_RUMVitalEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces?) {
        switch swift {
        case nil: self = .none
        case .bluetooth?: self = .bluetooth
        case .cellular?: self = .cellular
        case .ethernet?: self = .ethernet
        case .wifi?: self = .wifi
        case .wimax?: self = .wimax
        case .mixed?: self = .mixed
        case .other?: self = .other
        case .unknown?: self = .unknown
        case .interfacesNone?: self = .interfacesNone
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces? {
        switch self {
        case .none: return nil
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .interfacesNone: return .interfacesNone
        }
    }

    case none
    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case interfacesNone
}

@objc(DDRUMVitalEventRUMConnectivityStatus)
@_spi(objc)
public enum objc_RUMVitalEventRUMConnectivityStatus: Int {
    internal init(swift: RUMConnectivity.Status) {
        switch swift {
        case .connected: self = .connected
        case .notConnected: self = .notConnected
        case .maybe: self = .maybe
        }
    }

    internal var toSwift: RUMConnectivity.Status {
        switch self {
        case .connected: return .connected
        case .notConnected: return .notConnected
        case .maybe: return .maybe
        }
    }

    case connected
    case notConnected
    case maybe
}

@objc(DDRUMVitalEventContainer)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventContainer: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var source: objc_RUMVitalEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    public var view: objc_RUMVitalEventContainerView {
        objc_RUMVitalEventContainerView(root: root)
    }
}

@objc(DDRUMVitalEventContainerSource)
@_spi(objc)
public enum objc_RUMVitalEventContainerSource: Int {
    internal init(swift: RUMVitalEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMVitalEvent.Container.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMVitalEventContainerView)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventContainerView: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc(DDRUMVitalEventRUMEventAttributes)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMEventAttributes: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var contextInfo: [String: Any] {
        set { root.swiftModel.context!.contextInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.context!.contextInfo.dd.objCAttributes }
    }
}

@objc(DDRUMVitalEventDevice)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDevice: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    public var batteryLevel: NSNumber? {
        root.swiftModel.device!.batteryLevel as NSNumber?
    }

    public var brand: String? {
        root.swiftModel.device!.brand
    }

    public var brightnessLevel: NSNumber? {
        root.swiftModel.device!.brightnessLevel as NSNumber?
    }

    public var locale: String? {
        root.swiftModel.device!.locale
    }

    public var locales: [String]? {
        root.swiftModel.device!.locales
    }

    public var model: String? {
        root.swiftModel.device!.model
    }

    public var name: String? {
        root.swiftModel.device!.name
    }

    public var powerSavingMode: NSNumber? {
        root.swiftModel.device!.powerSavingMode as NSNumber?
    }

    public var timeZone: String? {
        root.swiftModel.device!.timeZone
    }

    public var type: objc_RUMVitalEventDeviceDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc(DDRUMVitalEventDeviceDeviceType)
@_spi(objc)
public enum objc_RUMVitalEventDeviceDeviceType: Int {
    internal init(swift: Device.DeviceType?) {
        switch swift {
        case nil: self = .none
        case .mobile?: self = .mobile
        case .desktop?: self = .desktop
        case .tablet?: self = .tablet
        case .tv?: self = .tv
        case .gamingConsole?: self = .gamingConsole
        case .bot?: self = .bot
        case .other?: self = .other
        }
    }

    internal var toSwift: Device.DeviceType? {
        switch self {
        case .none: return nil
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case none
    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc(DDRUMVitalEventDisplay)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDisplay: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var viewport: objc_RUMVitalEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? objc_RUMVitalEventDisplayViewport(root: root) : nil
    }
}

@objc(DDRUMVitalEventDisplayViewport)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventDisplayViewport: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc(DDRUMVitalEventOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventOperatingSystem: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.os!.build
    }

    public var name: String {
        root.swiftModel.os!.name
    }

    public var version: String {
        root.swiftModel.os!.version
    }

    public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc(DDRUMVitalEventSession)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventSession: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    public var id: String {
        root.swiftModel.session.id
    }

    public var type: objc_RUMVitalEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc(DDRUMVitalEventSessionRUMSessionType)
@_spi(objc)
public enum objc_RUMVitalEventSessionRUMSessionType: Int {
    internal init(swift: RUMSessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMSessionType {
        switch self {
        case .user: return .user
        case .synthetics: return .synthetics
        case .ciTest: return .ciTest
        }
    }

    case user
    case synthetics
    case ciTest
}

@objc(DDRUMVitalEventSource)
@_spi(objc)
public enum objc_RUMVitalEventSource: Int {
    internal init(swift: RUMVitalEvent.Source?) {
        switch swift {
        case nil: self = .none
        case .android?: self = .android
        case .ios?: self = .ios
        case .browser?: self = .browser
        case .flutter?: self = .flutter
        case .reactNative?: self = .reactNative
        case .roku?: self = .roku
        case .unity?: self = .unity
        case .kotlinMultiplatform?: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: RUMVitalEvent.Source? {
        switch self {
        case .none: return nil
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
    case kotlinMultiplatform
}

@objc(DDRUMVitalEventRUMSyntheticsTest)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMSyntheticsTest: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc(DDRUMVitalEventRUMUser)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventRUMUser: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var anonymousId: String? {
        root.swiftModel.usr!.anonymousId
    }

    public var email: String? {
        root.swiftModel.usr!.email
    }

    public var id: String? {
        root.swiftModel.usr!.id
    }

    public var name: String? {
        root.swiftModel.usr!.name
    }

    public var usrInfo: [String: Any] {
        set { root.swiftModel.usr!.usrInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.usr!.usrInfo.dd.objCAttributes }
    }
}

@objc(DDRUMVitalEventView)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventView: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view.id
    }

    public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc(DDRUMVitalEventVital)
@objcMembers
@_spi(objc)
public class objc_RUMVitalEventVital: NSObject {
    internal let root: objc_RUMVitalEvent

    internal init(root: objc_RUMVitalEvent) {
        self.root = root
    }

    public var custom: [String: NSNumber]? {
        root.swiftModel.vital.custom as [String: NSNumber]?
    }

    public var vitalDescription: String? {
        root.swiftModel.vital.vitalDescription
    }

    public var duration: NSNumber? {
        root.swiftModel.vital.duration as NSNumber?
    }

    public var id: String {
        root.swiftModel.vital.id
    }

    public var name: String? {
        root.swiftModel.vital.name
    }

    public var type: objc_RUMVitalEventVitalVitalType {
        .init(swift: root.swiftModel.vital.type)
    }
}

@objc(DDRUMVitalEventVitalVitalType)
@_spi(objc)
public enum objc_RUMVitalEventVitalVitalType: Int {
    internal init(swift: RUMVitalEvent.Vital.VitalType) {
        switch swift {
        case .duration: self = .duration
        }
    }

    internal var toSwift: RUMVitalEvent.Vital.VitalType {
        switch self {
        case .duration: return .duration
        }
    }

    case duration
}

@objc(DDTelemetryErrorEvent)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEvent: NSObject {
    public internal(set) var swiftModel: TelemetryErrorEvent
    internal var root: objc_TelemetryErrorEvent { self }

    public init(swiftModel: TelemetryErrorEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_TelemetryErrorEventDD {
        objc_TelemetryErrorEventDD(root: root)
    }

    public var action: objc_TelemetryErrorEventAction? {
        root.swiftModel.action != nil ? objc_TelemetryErrorEventAction(root: root) : nil
    }

    public var application: objc_TelemetryErrorEventApplication? {
        root.swiftModel.application != nil ? objc_TelemetryErrorEventApplication(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var effectiveSampleRate: NSNumber? {
        root.swiftModel.effectiveSampleRate as NSNumber?
    }

    public var experimentalFeatures: [String]? {
        root.swiftModel.experimentalFeatures
    }

    public var service: String {
        root.swiftModel.service
    }

    public var session: objc_TelemetryErrorEventSession? {
        root.swiftModel.session != nil ? objc_TelemetryErrorEventSession(root: root) : nil
    }

    public var source: objc_TelemetryErrorEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var telemetry: objc_TelemetryErrorEventTelemetry {
        objc_TelemetryErrorEventTelemetry(root: root)
    }

    public var type: String {
        root.swiftModel.type
    }

    public var version: String {
        root.swiftModel.version
    }

    public var view: objc_TelemetryErrorEventView? {
        root.swiftModel.view != nil ? objc_TelemetryErrorEventView(root: root) : nil
    }
}

@objc(DDTelemetryErrorEventDD)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventDD: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }
}

@objc(DDTelemetryErrorEventAction)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventAction: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.action!.id
    }
}

@objc(DDTelemetryErrorEventApplication)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventApplication: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.application!.id
    }
}

@objc(DDTelemetryErrorEventSession)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventSession: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.session!.id
    }
}

@objc(DDTelemetryErrorEventSource)
@_spi(objc)
public enum objc_TelemetryErrorEventSource: Int {
    internal init(swift: TelemetryErrorEvent.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: TelemetryErrorEvent.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case unity
    case kotlinMultiplatform
}

@objc(DDTelemetryErrorEventTelemetry)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventTelemetry: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var device: objc_TelemetryErrorEventTelemetryRUMTelemetryDevice? {
        root.swiftModel.telemetry.device != nil ? objc_TelemetryErrorEventTelemetryRUMTelemetryDevice(root: root) : nil
    }

    public var error: objc_TelemetryErrorEventTelemetryError? {
        root.swiftModel.telemetry.error != nil ? objc_TelemetryErrorEventTelemetryError(root: root) : nil
    }

    public var message: String {
        root.swiftModel.telemetry.message
    }

    public var os: objc_TelemetryErrorEventTelemetryRUMTelemetryOperatingSystem? {
        root.swiftModel.telemetry.os != nil ? objc_TelemetryErrorEventTelemetryRUMTelemetryOperatingSystem(root: root) : nil
    }

    public var status: String {
        root.swiftModel.telemetry.status
    }

    public var type: String? {
        root.swiftModel.telemetry.type
    }

    public var telemetryInfo: [String: Any] {
        set { root.swiftModel.telemetry.telemetryInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.telemetry.telemetryInfo.dd.objCAttributes }
    }
}

@objc(DDTelemetryErrorEventTelemetryRUMTelemetryDevice)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventTelemetryRUMTelemetryDevice: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.telemetry.device!.architecture
    }

    public var brand: String? {
        root.swiftModel.telemetry.device!.brand
    }

    public var model: String? {
        root.swiftModel.telemetry.device!.model
    }
}

@objc(DDTelemetryErrorEventTelemetryError)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventTelemetryError: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var kind: String? {
        root.swiftModel.telemetry.error!.kind
    }

    public var stack: String? {
        root.swiftModel.telemetry.error!.stack
    }
}

@objc(DDTelemetryErrorEventTelemetryRUMTelemetryOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventTelemetryRUMTelemetryOperatingSystem: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.telemetry.os!.build
    }

    public var name: String? {
        root.swiftModel.telemetry.os!.name
    }

    public var version: String? {
        root.swiftModel.telemetry.os!.version
    }
}

@objc(DDTelemetryErrorEventView)
@objcMembers
@_spi(objc)
public class objc_TelemetryErrorEventView: NSObject {
    internal let root: objc_TelemetryErrorEvent

    internal init(root: objc_TelemetryErrorEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view!.id
    }
}

@objc(DDTelemetryDebugEvent)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEvent: NSObject {
    public internal(set) var swiftModel: TelemetryDebugEvent
    internal var root: objc_TelemetryDebugEvent { self }

    public init(swiftModel: TelemetryDebugEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_TelemetryDebugEventDD {
        objc_TelemetryDebugEventDD(root: root)
    }

    public var action: objc_TelemetryDebugEventAction? {
        root.swiftModel.action != nil ? objc_TelemetryDebugEventAction(root: root) : nil
    }

    public var application: objc_TelemetryDebugEventApplication? {
        root.swiftModel.application != nil ? objc_TelemetryDebugEventApplication(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var effectiveSampleRate: NSNumber? {
        root.swiftModel.effectiveSampleRate as NSNumber?
    }

    public var experimentalFeatures: [String]? {
        root.swiftModel.experimentalFeatures
    }

    public var service: String {
        root.swiftModel.service
    }

    public var session: objc_TelemetryDebugEventSession? {
        root.swiftModel.session != nil ? objc_TelemetryDebugEventSession(root: root) : nil
    }

    public var source: objc_TelemetryDebugEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var telemetry: objc_TelemetryDebugEventTelemetry {
        objc_TelemetryDebugEventTelemetry(root: root)
    }

    public var type: String {
        root.swiftModel.type
    }

    public var version: String {
        root.swiftModel.version
    }

    public var view: objc_TelemetryDebugEventView? {
        root.swiftModel.view != nil ? objc_TelemetryDebugEventView(root: root) : nil
    }
}

@objc(DDTelemetryDebugEventDD)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventDD: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }
}

@objc(DDTelemetryDebugEventAction)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventAction: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.action!.id
    }
}

@objc(DDTelemetryDebugEventApplication)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventApplication: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.application!.id
    }
}

@objc(DDTelemetryDebugEventSession)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventSession: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.session!.id
    }
}

@objc(DDTelemetryDebugEventSource)
@_spi(objc)
public enum objc_TelemetryDebugEventSource: Int {
    internal init(swift: TelemetryDebugEvent.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: TelemetryDebugEvent.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case unity
    case kotlinMultiplatform
}

@objc(DDTelemetryDebugEventTelemetry)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventTelemetry: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var device: objc_TelemetryDebugEventTelemetryRUMTelemetryDevice? {
        root.swiftModel.telemetry.device != nil ? objc_TelemetryDebugEventTelemetryRUMTelemetryDevice(root: root) : nil
    }

    public var message: String {
        root.swiftModel.telemetry.message
    }

    public var os: objc_TelemetryDebugEventTelemetryRUMTelemetryOperatingSystem? {
        root.swiftModel.telemetry.os != nil ? objc_TelemetryDebugEventTelemetryRUMTelemetryOperatingSystem(root: root) : nil
    }

    public var status: String {
        root.swiftModel.telemetry.status
    }

    public var type: String? {
        root.swiftModel.telemetry.type
    }

    public var telemetryInfo: [String: Any] {
        set { root.swiftModel.telemetry.telemetryInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.telemetry.telemetryInfo.dd.objCAttributes }
    }
}

@objc(DDTelemetryDebugEventTelemetryRUMTelemetryDevice)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventTelemetryRUMTelemetryDevice: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.telemetry.device!.architecture
    }

    public var brand: String? {
        root.swiftModel.telemetry.device!.brand
    }

    public var model: String? {
        root.swiftModel.telemetry.device!.model
    }
}

@objc(DDTelemetryDebugEventTelemetryRUMTelemetryOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventTelemetryRUMTelemetryOperatingSystem: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.telemetry.os!.build
    }

    public var name: String? {
        root.swiftModel.telemetry.os!.name
    }

    public var version: String? {
        root.swiftModel.telemetry.os!.version
    }
}

@objc(DDTelemetryDebugEventView)
@objcMembers
@_spi(objc)
public class objc_TelemetryDebugEventView: NSObject {
    internal let root: objc_TelemetryDebugEvent

    internal init(root: objc_TelemetryDebugEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view!.id
    }
}

@objc(DDTelemetryConfigurationEvent)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEvent: NSObject {
    public internal(set) var swiftModel: TelemetryConfigurationEvent
    internal var root: objc_TelemetryConfigurationEvent { self }

    public init(swiftModel: TelemetryConfigurationEvent) {
        self.swiftModel = swiftModel
    }

    public var dd: objc_TelemetryConfigurationEventDD {
        objc_TelemetryConfigurationEventDD(root: root)
    }

    public var action: objc_TelemetryConfigurationEventAction? {
        root.swiftModel.action != nil ? objc_TelemetryConfigurationEventAction(root: root) : nil
    }

    public var application: objc_TelemetryConfigurationEventApplication? {
        root.swiftModel.application != nil ? objc_TelemetryConfigurationEventApplication(root: root) : nil
    }

    public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    public var effectiveSampleRate: NSNumber? {
        root.swiftModel.effectiveSampleRate as NSNumber?
    }

    public var experimentalFeatures: [String]? {
        root.swiftModel.experimentalFeatures
    }

    public var service: String {
        root.swiftModel.service
    }

    public var session: objc_TelemetryConfigurationEventSession? {
        root.swiftModel.session != nil ? objc_TelemetryConfigurationEventSession(root: root) : nil
    }

    public var source: objc_TelemetryConfigurationEventSource {
        .init(swift: root.swiftModel.source)
    }

    public var telemetry: objc_TelemetryConfigurationEventTelemetry {
        objc_TelemetryConfigurationEventTelemetry(root: root)
    }

    public var type: String {
        root.swiftModel.type
    }

    public var version: String {
        root.swiftModel.version
    }

    public var view: objc_TelemetryConfigurationEventView? {
        root.swiftModel.view != nil ? objc_TelemetryConfigurationEventView(root: root) : nil
    }
}

@objc(DDTelemetryConfigurationEventDD)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventDD: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }
}

@objc(DDTelemetryConfigurationEventAction)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventAction: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.action!.id
    }
}

@objc(DDTelemetryConfigurationEventApplication)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventApplication: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.application!.id
    }
}

@objc(DDTelemetryConfigurationEventSession)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventSession: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.session!.id
    }
}

@objc(DDTelemetryConfigurationEventSource)
@_spi(objc)
public enum objc_TelemetryConfigurationEventSource: Int {
    internal init(swift: TelemetryConfigurationEvent.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .unity: self = .unity
        case .kotlinMultiplatform: self = .kotlinMultiplatform
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case unity
    case kotlinMultiplatform
}

@objc(DDTelemetryConfigurationEventTelemetry)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetry: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var configuration: objc_TelemetryConfigurationEventTelemetryConfiguration {
        objc_TelemetryConfigurationEventTelemetryConfiguration(root: root)
    }

    public var device: objc_TelemetryConfigurationEventTelemetryRUMTelemetryDevice? {
        root.swiftModel.telemetry.device != nil ? objc_TelemetryConfigurationEventTelemetryRUMTelemetryDevice(root: root) : nil
    }

    public var os: objc_TelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem? {
        root.swiftModel.telemetry.os != nil ? objc_TelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem(root: root) : nil
    }

    public var type: String {
        root.swiftModel.telemetry.type
    }

    public var telemetryInfo: [String: Any] {
        set { root.swiftModel.telemetry.telemetryInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.telemetry.telemetryInfo.dd.objCAttributes }
    }
}

@objc(DDTelemetryConfigurationEventTelemetryConfiguration)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetryConfiguration: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var actionNameAttribute: String? {
        root.swiftModel.telemetry.configuration.actionNameAttribute
    }

    public var allowFallbackToLocalStorage: NSNumber? {
        root.swiftModel.telemetry.configuration.allowFallbackToLocalStorage as NSNumber?
    }

    public var allowUntrustedEvents: NSNumber? {
        root.swiftModel.telemetry.configuration.allowUntrustedEvents as NSNumber?
    }

    public var appHangThreshold: NSNumber? {
        root.swiftModel.telemetry.configuration.appHangThreshold as NSNumber?
    }

    public var backgroundTasksEnabled: NSNumber? {
        root.swiftModel.telemetry.configuration.backgroundTasksEnabled as NSNumber?
    }

    public var batchProcessingLevel: NSNumber? {
        root.swiftModel.telemetry.configuration.batchProcessingLevel as NSNumber?
    }

    public var batchSize: NSNumber? {
        root.swiftModel.telemetry.configuration.batchSize as NSNumber?
    }

    public var batchUploadFrequency: NSNumber? {
        root.swiftModel.telemetry.configuration.batchUploadFrequency as NSNumber?
    }

    public var compressIntakeRequests: NSNumber? {
        root.swiftModel.telemetry.configuration.compressIntakeRequests as NSNumber?
    }

    public var dartVersion: String? {
        set { root.swiftModel.telemetry.configuration.dartVersion = newValue }
        get { root.swiftModel.telemetry.configuration.dartVersion }
    }

    public var defaultPrivacyLevel: String? {
        set { root.swiftModel.telemetry.configuration.defaultPrivacyLevel = newValue }
        get { root.swiftModel.telemetry.configuration.defaultPrivacyLevel }
    }

    public var enablePrivacyForActionName: NSNumber? {
        set { root.swiftModel.telemetry.configuration.enablePrivacyForActionName = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.enablePrivacyForActionName as NSNumber? }
    }

    public var forwardConsoleLogs: objc_TelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs? {
        root.swiftModel.telemetry.configuration.forwardConsoleLogs != nil ? objc_TelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs(root: root) : nil
    }

    public var forwardErrorsToLogs: NSNumber? {
        root.swiftModel.telemetry.configuration.forwardErrorsToLogs as NSNumber?
    }

    public var forwardReports: objc_TelemetryConfigurationEventTelemetryConfigurationForwardReports? {
        root.swiftModel.telemetry.configuration.forwardReports != nil ? objc_TelemetryConfigurationEventTelemetryConfigurationForwardReports(root: root) : nil
    }

    public var imagePrivacyLevel: String? {
        set { root.swiftModel.telemetry.configuration.imagePrivacyLevel = newValue }
        get { root.swiftModel.telemetry.configuration.imagePrivacyLevel }
    }

    public var initializationType: String? {
        set { root.swiftModel.telemetry.configuration.initializationType = newValue }
        get { root.swiftModel.telemetry.configuration.initializationType }
    }

    public var invTimeThresholdMs: NSNumber? {
        root.swiftModel.telemetry.configuration.invTimeThresholdMs as NSNumber?
    }

    public var isMainProcess: NSNumber? {
        root.swiftModel.telemetry.configuration.isMainProcess as NSNumber?
    }

    public var mobileVitalsUpdatePeriod: NSNumber? {
        set { root.swiftModel.telemetry.configuration.mobileVitalsUpdatePeriod = newValue?.int64Value }
        get { root.swiftModel.telemetry.configuration.mobileVitalsUpdatePeriod as NSNumber? }
    }

    public var numberOfDisplays: NSNumber? {
        root.swiftModel.telemetry.configuration.numberOfDisplays as NSNumber?
    }

    public var plugins: [objc_TelemetryConfigurationEventTelemetryConfigurationPlugins]? {
        set { root.swiftModel.telemetry.configuration.plugins = newValue?.map { $0.swiftModel } }
        get { root.swiftModel.telemetry.configuration.plugins?.map { objc_TelemetryConfigurationEventTelemetryConfigurationPlugins(swiftModel: $0) } }
    }

    public var premiumSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.premiumSampleRate as NSNumber?
    }

    public var reactNativeVersion: String? {
        set { root.swiftModel.telemetry.configuration.reactNativeVersion = newValue }
        get { root.swiftModel.telemetry.configuration.reactNativeVersion }
    }

    public var reactVersion: String? {
        set { root.swiftModel.telemetry.configuration.reactVersion = newValue }
        get { root.swiftModel.telemetry.configuration.reactVersion }
    }

    public var replaySampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.replaySampleRate as NSNumber?
    }

    public var selectedTracingPropagators: [Int]? {
        root.swiftModel.telemetry.configuration.selectedTracingPropagators?.map { objc_TelemetryConfigurationEventTelemetryConfigurationSelectedTracingPropagators(swift: $0).rawValue }
    }

    public var sendLogsAfterSessionExpiration: NSNumber? {
        set { root.swiftModel.telemetry.configuration.sendLogsAfterSessionExpiration = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.sendLogsAfterSessionExpiration as NSNumber? }
    }

    public var sessionPersistence: objc_TelemetryConfigurationEventTelemetryConfigurationSessionPersistence {
        .init(swift: root.swiftModel.telemetry.configuration.sessionPersistence)
    }

    public var sessionReplaySampleRate: NSNumber? {
        set { root.swiftModel.telemetry.configuration.sessionReplaySampleRate = newValue?.int64Value }
        get { root.swiftModel.telemetry.configuration.sessionReplaySampleRate as NSNumber? }
    }

    public var sessionSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.sessionSampleRate as NSNumber?
    }

    public var silentMultipleInit: NSNumber? {
        root.swiftModel.telemetry.configuration.silentMultipleInit as NSNumber?
    }

    public var startRecordingImmediately: NSNumber? {
        set { root.swiftModel.telemetry.configuration.startRecordingImmediately = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.startRecordingImmediately as NSNumber? }
    }

    public var startSessionReplayRecordingManually: NSNumber? {
        set { root.swiftModel.telemetry.configuration.startSessionReplayRecordingManually = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.startSessionReplayRecordingManually as NSNumber? }
    }

    public var storeContextsAcrossPages: NSNumber? {
        root.swiftModel.telemetry.configuration.storeContextsAcrossPages as NSNumber?
    }

    public var swiftuiActionTrackingEnabled: NSNumber? {
        set { root.swiftModel.telemetry.configuration.swiftuiActionTrackingEnabled = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.swiftuiActionTrackingEnabled as NSNumber? }
    }

    public var swiftuiViewTrackingEnabled: NSNumber? {
        set { root.swiftModel.telemetry.configuration.swiftuiViewTrackingEnabled = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.swiftuiViewTrackingEnabled as NSNumber? }
    }

    public var telemetryConfigurationSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.telemetryConfigurationSampleRate as NSNumber?
    }

    public var telemetrySampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.telemetrySampleRate as NSNumber?
    }

    public var telemetryUsageSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.telemetryUsageSampleRate as NSNumber?
    }

    public var textAndInputPrivacyLevel: String? {
        set { root.swiftModel.telemetry.configuration.textAndInputPrivacyLevel = newValue }
        get { root.swiftModel.telemetry.configuration.textAndInputPrivacyLevel }
    }

    public var tnsTimeThresholdMs: NSNumber? {
        root.swiftModel.telemetry.configuration.tnsTimeThresholdMs as NSNumber?
    }

    public var touchPrivacyLevel: String? {
        set { root.swiftModel.telemetry.configuration.touchPrivacyLevel = newValue }
        get { root.swiftModel.telemetry.configuration.touchPrivacyLevel }
    }

    public var traceContextInjection: objc_TelemetryConfigurationEventTelemetryConfigurationTraceContextInjection {
        set { root.swiftModel.telemetry.configuration.traceContextInjection = newValue.toSwift }
        get { .init(swift: root.swiftModel.telemetry.configuration.traceContextInjection) }
    }

    public var traceSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.traceSampleRate as NSNumber?
    }

    public var tracerApi: String? {
        set { root.swiftModel.telemetry.configuration.tracerApi = newValue }
        get { root.swiftModel.telemetry.configuration.tracerApi }
    }

    public var tracerApiVersion: String? {
        set { root.swiftModel.telemetry.configuration.tracerApiVersion = newValue }
        get { root.swiftModel.telemetry.configuration.tracerApiVersion }
    }

    public var trackAnonymousUser: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackAnonymousUser = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackAnonymousUser as NSNumber? }
    }

    public var trackBackgroundEvents: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackBackgroundEvents = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackBackgroundEvents as NSNumber? }
    }

    public var trackBfcacheViews: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackBfcacheViews = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackBfcacheViews as NSNumber? }
    }

    public var trackCrossPlatformLongTasks: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackCrossPlatformLongTasks = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackCrossPlatformLongTasks as NSNumber? }
    }

    public var trackErrors: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackErrors = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackErrors as NSNumber? }
    }

    public var trackFeatureFlagsForEvents: [Int]? {
        root.swiftModel.telemetry.configuration.trackFeatureFlagsForEvents?.map { objc_TelemetryConfigurationEventTelemetryConfigurationTrackFeatureFlagsForEvents(swift: $0).rawValue }
    }

    public var trackFlutterPerformance: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackFlutterPerformance = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackFlutterPerformance as NSNumber? }
    }

    public var trackFrustrations: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackFrustrations = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackFrustrations as NSNumber? }
    }

    public var trackInteractions: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackInteractions = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackInteractions as NSNumber? }
    }

    public var trackLongTask: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackLongTask = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackLongTask as NSNumber? }
    }

    public var trackNativeErrors: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNativeErrors = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNativeErrors as NSNumber? }
    }

    public var trackNativeLongTasks: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNativeLongTasks = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNativeLongTasks as NSNumber? }
    }

    public var trackNativeViews: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNativeViews = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNativeViews as NSNumber? }
    }

    public var trackNetworkRequests: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNetworkRequests = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNetworkRequests as NSNumber? }
    }

    public var trackResources: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackResources = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackResources as NSNumber? }
    }

    public var trackSessionAcrossSubdomains: NSNumber? {
        root.swiftModel.telemetry.configuration.trackSessionAcrossSubdomains as NSNumber?
    }

    public var trackUserInteractions: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackUserInteractions = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackUserInteractions as NSNumber? }
    }

    public var trackViewsManually: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackViewsManually = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackViewsManually as NSNumber? }
    }

    public var trackingConsent: objc_TelemetryConfigurationEventTelemetryConfigurationTrackingConsent {
        .init(swift: root.swiftModel.telemetry.configuration.trackingConsent)
    }

    public var unityVersion: String? {
        set { root.swiftModel.telemetry.configuration.unityVersion = newValue }
        get { root.swiftModel.telemetry.configuration.unityVersion }
    }

    public var useAllowedTracingOrigins: NSNumber? {
        root.swiftModel.telemetry.configuration.useAllowedTracingOrigins as NSNumber?
    }

    public var useAllowedTracingUrls: NSNumber? {
        root.swiftModel.telemetry.configuration.useAllowedTracingUrls as NSNumber?
    }

    public var useAllowedTrackingOrigins: NSNumber? {
        set { root.swiftModel.telemetry.configuration.useAllowedTrackingOrigins = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.useAllowedTrackingOrigins as NSNumber? }
    }

    public var useBeforeSend: NSNumber? {
        root.swiftModel.telemetry.configuration.useBeforeSend as NSNumber?
    }

    public var useCrossSiteSessionCookie: NSNumber? {
        root.swiftModel.telemetry.configuration.useCrossSiteSessionCookie as NSNumber?
    }

    public var useExcludedActivityUrls: NSNumber? {
        root.swiftModel.telemetry.configuration.useExcludedActivityUrls as NSNumber?
    }

    public var useFirstPartyHosts: NSNumber? {
        set { root.swiftModel.telemetry.configuration.useFirstPartyHosts = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.useFirstPartyHosts as NSNumber? }
    }

    public var useLocalEncryption: NSNumber? {
        root.swiftModel.telemetry.configuration.useLocalEncryption as NSNumber?
    }

    public var usePartitionedCrossSiteSessionCookie: NSNumber? {
        root.swiftModel.telemetry.configuration.usePartitionedCrossSiteSessionCookie as NSNumber?
    }

    public var usePciIntake: NSNumber? {
        set { root.swiftModel.telemetry.configuration.usePciIntake = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.usePciIntake as NSNumber? }
    }

    public var useProxy: NSNumber? {
        set { root.swiftModel.telemetry.configuration.useProxy = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.useProxy as NSNumber? }
    }

    public var useSecureSessionCookie: NSNumber? {
        root.swiftModel.telemetry.configuration.useSecureSessionCookie as NSNumber?
    }

    public var useTracing: NSNumber? {
        root.swiftModel.telemetry.configuration.useTracing as NSNumber?
    }

    public var useWorkerUrl: NSNumber? {
        root.swiftModel.telemetry.configuration.useWorkerUrl as NSNumber?
    }

    public var viewTrackingStrategy: objc_TelemetryConfigurationEventTelemetryConfigurationViewTrackingStrategy {
        .init(swift: root.swiftModel.telemetry.configuration.viewTrackingStrategy)
    }
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.telemetry.configuration.forwardConsoleLogs else {
            return nil
        }
        return value
    }

    public var string: String? {
        guard case .string(let value) = root.swiftModel.telemetry.configuration.forwardConsoleLogs else {
            return nil
        }
        return value
    }
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationForwardReports)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetryConfigurationForwardReports: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.telemetry.configuration.forwardReports else {
            return nil
        }
        return value
    }

    public var string: String? {
        guard case .string(let value) = root.swiftModel.telemetry.configuration.forwardReports else {
            return nil
        }
        return value
    }
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationPlugins)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetryConfigurationPlugins: NSObject {
    internal var swiftModel: TelemetryConfigurationEvent.Telemetry.Configuration.Plugins
    internal var root: objc_TelemetryConfigurationEventTelemetryConfigurationPlugins { self }

    internal init(swiftModel: TelemetryConfigurationEvent.Telemetry.Configuration.Plugins) {
        self.swiftModel = swiftModel
    }

    public var name: String {
        root.swiftModel.name
    }

    public var pluginsInfo: [String: Any] {
        set { root.swiftModel.pluginsInfo = newValue.dd.swiftAttributes }
        get { root.swiftModel.pluginsInfo.dd.objCAttributes }
    }
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationSelectedTracingPropagators)
@_spi(objc)
public enum objc_TelemetryConfigurationEventTelemetryConfigurationSelectedTracingPropagators: Int {
    internal init(swift: TelemetryConfigurationEvent.Telemetry.Configuration.SelectedTracingPropagators?) {
        switch swift {
        case nil: self = .none
        case .datadog?: self = .datadog
        case .b3?: self = .b3
        case .b3multi?: self = .b3multi
        case .tracecontext?: self = .tracecontext
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Telemetry.Configuration.SelectedTracingPropagators? {
        switch self {
        case .none: return nil
        case .datadog: return .datadog
        case .b3: return .b3
        case .b3multi: return .b3multi
        case .tracecontext: return .tracecontext
        }
    }

    case none
    case datadog
    case b3
    case b3multi
    case tracecontext
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationSessionPersistence)
@_spi(objc)
public enum objc_TelemetryConfigurationEventTelemetryConfigurationSessionPersistence: Int {
    internal init(swift: TelemetryConfigurationEvent.Telemetry.Configuration.SessionPersistence?) {
        switch swift {
        case nil: self = .none
        case .localStorage?: self = .localStorage
        case .cookie?: self = .cookie
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Telemetry.Configuration.SessionPersistence? {
        switch self {
        case .none: return nil
        case .localStorage: return .localStorage
        case .cookie: return .cookie
        }
    }

    case none
    case localStorage
    case cookie
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationTraceContextInjection)
@_spi(objc)
public enum objc_TelemetryConfigurationEventTelemetryConfigurationTraceContextInjection: Int {
    internal init(swift: TelemetryConfigurationEvent.Telemetry.Configuration.TraceContextInjection?) {
        switch swift {
        case nil: self = .none
        case .all?: self = .all
        case .sampled?: self = .sampled
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Telemetry.Configuration.TraceContextInjection? {
        switch self {
        case .none: return nil
        case .all: return .all
        case .sampled: return .sampled
        }
    }

    case none
    case all
    case sampled
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationTrackFeatureFlagsForEvents)
@_spi(objc)
public enum objc_TelemetryConfigurationEventTelemetryConfigurationTrackFeatureFlagsForEvents: Int {
    internal init(swift: TelemetryConfigurationEvent.Telemetry.Configuration.TrackFeatureFlagsForEvents?) {
        switch swift {
        case nil: self = .none
        case .vital?: self = .vital
        case .resource?: self = .resource
        case .action?: self = .action
        case .longTask?: self = .longTask
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Telemetry.Configuration.TrackFeatureFlagsForEvents? {
        switch self {
        case .none: return nil
        case .vital: return .vital
        case .resource: return .resource
        case .action: return .action
        case .longTask: return .longTask
        }
    }

    case none
    case vital
    case resource
    case action
    case longTask
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationTrackingConsent)
@_spi(objc)
public enum objc_TelemetryConfigurationEventTelemetryConfigurationTrackingConsent: Int {
    internal init(swift: TelemetryConfigurationEvent.Telemetry.Configuration.TrackingConsent?) {
        switch swift {
        case nil: self = .none
        case .granted?: self = .granted
        case .notGranted?: self = .notGranted
        case .pending?: self = .pending
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Telemetry.Configuration.TrackingConsent? {
        switch self {
        case .none: return nil
        case .granted: return .granted
        case .notGranted: return .notGranted
        case .pending: return .pending
        }
    }

    case none
    case granted
    case notGranted
    case pending
}

@objc(DDTelemetryConfigurationEventTelemetryConfigurationViewTrackingStrategy)
@_spi(objc)
public enum objc_TelemetryConfigurationEventTelemetryConfigurationViewTrackingStrategy: Int {
    internal init(swift: TelemetryConfigurationEvent.Telemetry.Configuration.ViewTrackingStrategy?) {
        switch swift {
        case nil: self = .none
        case .activityViewTrackingStrategy?: self = .activityViewTrackingStrategy
        case .fragmentViewTrackingStrategy?: self = .fragmentViewTrackingStrategy
        case .mixedViewTrackingStrategy?: self = .mixedViewTrackingStrategy
        case .navigationViewTrackingStrategy?: self = .navigationViewTrackingStrategy
        }
    }

    internal var toSwift: TelemetryConfigurationEvent.Telemetry.Configuration.ViewTrackingStrategy? {
        switch self {
        case .none: return nil
        case .activityViewTrackingStrategy: return .activityViewTrackingStrategy
        case .fragmentViewTrackingStrategy: return .fragmentViewTrackingStrategy
        case .mixedViewTrackingStrategy: return .mixedViewTrackingStrategy
        case .navigationViewTrackingStrategy: return .navigationViewTrackingStrategy
        }
    }

    case none
    case activityViewTrackingStrategy
    case fragmentViewTrackingStrategy
    case mixedViewTrackingStrategy
    case navigationViewTrackingStrategy
}

@objc(DDTelemetryConfigurationEventTelemetryRUMTelemetryDevice)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetryRUMTelemetryDevice: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var architecture: String? {
        root.swiftModel.telemetry.device!.architecture
    }

    public var brand: String? {
        root.swiftModel.telemetry.device!.brand
    }

    public var model: String? {
        root.swiftModel.telemetry.device!.model
    }
}

@objc(DDTelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var build: String? {
        root.swiftModel.telemetry.os!.build
    }

    public var name: String? {
        root.swiftModel.telemetry.os!.name
    }

    public var version: String? {
        root.swiftModel.telemetry.os!.version
    }
}

@objc(DDTelemetryConfigurationEventView)
@objcMembers
@_spi(objc)
public class objc_TelemetryConfigurationEventView: NSObject {
    internal let root: objc_TelemetryConfigurationEvent

    internal init(root: objc_TelemetryConfigurationEvent) {
        self.root = root
    }

    public var id: String {
        root.swiftModel.view!.id
    }
}

// swiftlint:enable force_unwrapping

// Generated from https://github.com/DataDog/rum-events-format/tree/ca4ca9c6ce21f634f41cda2fdd95cacc4b5246b0
