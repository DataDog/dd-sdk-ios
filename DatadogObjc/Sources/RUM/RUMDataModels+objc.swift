/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogRUM

// This file was generated from JSON Schema. Do not modify it directly.

// swiftlint:disable force_unwrapping

@objc
public class DDRUMActionEvent: NSObject {
    internal var swiftModel: RUMActionEvent
    internal var root: DDRUMActionEvent { self }

    internal init(swiftModel: RUMActionEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDRUMActionEventDD {
        DDRUMActionEventDD(root: root)
    }

    @objc public var action: DDRUMActionEventAction {
        DDRUMActionEventAction(root: root)
    }

    @objc public var application: DDRUMActionEventApplication {
        DDRUMActionEventApplication(root: root)
    }

    @objc public var buildId: String? {
        root.swiftModel.buildId
    }

    @objc public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    @objc public var ciTest: DDRUMActionEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMActionEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMActionEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMActionEventRUMConnectivity(root: root) : nil
    }

    @objc public var container: DDRUMActionEventContainer? {
        root.swiftModel.container != nil ? DDRUMActionEventContainer(root: root) : nil
    }

    @objc public var context: DDRUMActionEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMActionEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var device: DDRUMActionEventRUMDevice? {
        root.swiftModel.device != nil ? DDRUMActionEventRUMDevice(root: root) : nil
    }

    @objc public var display: DDRUMActionEventDisplay? {
        root.swiftModel.display != nil ? DDRUMActionEventDisplay(root: root) : nil
    }

    @objc public var os: DDRUMActionEventRUMOperatingSystem? {
        root.swiftModel.os != nil ? DDRUMActionEventRUMOperatingSystem(root: root) : nil
    }

    @objc public var service: String? {
        root.swiftModel.service
    }

    @objc public var session: DDRUMActionEventSession {
        DDRUMActionEventSession(root: root)
    }

    @objc public var source: DDRUMActionEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var synthetics: DDRUMActionEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? DDRUMActionEventRUMSyntheticsTest(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var usr: DDRUMActionEventRUMUser? {
        root.swiftModel.usr != nil ? DDRUMActionEventRUMUser(root: root) : nil
    }

    @objc public var version: String? {
        root.swiftModel.version
    }

    @objc public var view: DDRUMActionEventView {
        DDRUMActionEventView(root: root)
    }
}

@objc
public class DDRUMActionEventDD: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var action: DDRUMActionEventDDAction? {
        root.swiftModel.dd.action != nil ? DDRUMActionEventDDAction(root: root) : nil
    }

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var configuration: DDRUMActionEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? DDRUMActionEventDDConfiguration(root: root) : nil
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMActionEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMActionEventDDSession(root: root) : nil
    }
}

@objc
public class DDRUMActionEventDDAction: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var position: DDRUMActionEventDDActionPosition? {
        root.swiftModel.dd.action!.position != nil ? DDRUMActionEventDDActionPosition(root: root) : nil
    }

    @objc public var target: DDRUMActionEventDDActionTarget? {
        root.swiftModel.dd.action!.target != nil ? DDRUMActionEventDDActionTarget(root: root) : nil
    }
}

@objc
public class DDRUMActionEventDDActionPosition: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var x: NSNumber {
        root.swiftModel.dd.action!.position!.x as NSNumber
    }

    @objc public var y: NSNumber {
        root.swiftModel.dd.action!.position!.y as NSNumber
    }
}

@objc
public class DDRUMActionEventDDActionTarget: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var height: NSNumber? {
        root.swiftModel.dd.action!.target!.height as NSNumber?
    }

    @objc public var selector: String? {
        root.swiftModel.dd.action!.target!.selector
    }

    @objc public var width: NSNumber? {
        root.swiftModel.dd.action!.target!.width as NSNumber?
    }
}

@objc
public class DDRUMActionEventDDConfiguration: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    @objc public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc
public class DDRUMActionEventDDSession: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMActionEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    @objc public var sessionPrecondition: DDRUMActionEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc
public enum DDRUMActionEventDDSessionPlan: Int {
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

@objc
public enum DDRUMActionEventDDSessionRUMSessionPrecondition: Int {
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

@objc
public class DDRUMActionEventAction: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var crash: DDRUMActionEventActionCrash? {
        root.swiftModel.action.crash != nil ? DDRUMActionEventActionCrash(root: root) : nil
    }

    @objc public var error: DDRUMActionEventActionError? {
        root.swiftModel.action.error != nil ? DDRUMActionEventActionError(root: root) : nil
    }

    @objc public var frustration: DDRUMActionEventActionFrustration? {
        root.swiftModel.action.frustration != nil ? DDRUMActionEventActionFrustration(root: root) : nil
    }

    @objc public var id: String? {
        root.swiftModel.action.id
    }

    @objc public var loadingTime: NSNumber? {
        root.swiftModel.action.loadingTime as NSNumber?
    }

    @objc public var longTask: DDRUMActionEventActionLongTask? {
        root.swiftModel.action.longTask != nil ? DDRUMActionEventActionLongTask(root: root) : nil
    }

    @objc public var resource: DDRUMActionEventActionResource? {
        root.swiftModel.action.resource != nil ? DDRUMActionEventActionResource(root: root) : nil
    }

    @objc public var target: DDRUMActionEventActionTarget? {
        root.swiftModel.action.target != nil ? DDRUMActionEventActionTarget(root: root) : nil
    }

    @objc public var type: DDRUMActionEventActionActionType {
        .init(swift: root.swiftModel.action.type)
    }
}

@objc
public class DDRUMActionEventActionCrash: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.action.crash!.count as NSNumber
    }
}

@objc
public class DDRUMActionEventActionError: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.action.error!.count as NSNumber
    }
}

@objc
public class DDRUMActionEventActionFrustration: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var type: [Int] {
        root.swiftModel.action.frustration!.type.map { DDRUMActionEventActionFrustrationFrustrationType(swift: $0).rawValue }
    }
}

@objc
public enum DDRUMActionEventActionFrustrationFrustrationType: Int {
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

@objc
public class DDRUMActionEventActionLongTask: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.action.longTask!.count as NSNumber
    }
}

@objc
public class DDRUMActionEventActionResource: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.action.resource!.count as NSNumber
    }
}

@objc
public class DDRUMActionEventActionTarget: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var name: String {
        set { root.swiftModel.action.target!.name = newValue }
        get { root.swiftModel.action.target!.name }
    }
}

@objc
public enum DDRUMActionEventActionActionType: Int {
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

@objc
public class DDRUMActionEventApplication: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application.id
    }
}

@objc
public class DDRUMActionEventRUMCITest: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc
public class DDRUMActionEventRUMConnectivity: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var cellular: DDRUMActionEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? DDRUMActionEventRUMConnectivityCellular(root: root) : nil
    }

    @objc public var effectiveType: DDRUMActionEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    @objc public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { DDRUMActionEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    @objc public var status: DDRUMActionEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc
public class DDRUMActionEventRUMConnectivityCellular: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    @objc public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc
public enum DDRUMActionEventRUMConnectivityEffectiveType: Int {
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

@objc
public enum DDRUMActionEventRUMConnectivityInterfaces: Int {
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

@objc
public enum DDRUMActionEventRUMConnectivityStatus: Int {
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

@objc
public class DDRUMActionEventContainer: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var source: DDRUMActionEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    @objc public var view: DDRUMActionEventContainerView {
        DDRUMActionEventContainerView(root: root)
    }
}

@objc
public enum DDRUMActionEventContainerSource: Int {
    internal init(swift: RUMActionEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
}

@objc
public class DDRUMActionEventContainerView: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc
public class DDRUMActionEventRUMEventAttributes: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var contextInfo: [String: Any] {
        root.swiftModel.context!.contextInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMActionEventRUMDevice: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.device!.model
    }

    @objc public var name: String? {
        root.swiftModel.device!.name
    }

    @objc public var type: DDRUMActionEventRUMDeviceRUMDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc
public enum DDRUMActionEventRUMDeviceRUMDeviceType: Int {
    internal init(swift: RUMDevice.RUMDeviceType) {
        switch swift {
        case .mobile: self = .mobile
        case .desktop: self = .desktop
        case .tablet: self = .tablet
        case .tv: self = .tv
        case .gamingConsole: self = .gamingConsole
        case .bot: self = .bot
        case .other: self = .other
        }
    }

    internal var toSwift: RUMDevice.RUMDeviceType {
        switch self {
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc
public class DDRUMActionEventDisplay: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var viewport: DDRUMActionEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? DDRUMActionEventDisplayViewport(root: root) : nil
    }
}

@objc
public class DDRUMActionEventDisplayViewport: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    @objc public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc
public class DDRUMActionEventRUMOperatingSystem: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.os!.build
    }

    @objc public var name: String {
        root.swiftModel.os!.name
    }

    @objc public var version: String {
        root.swiftModel.os!.version
    }

    @objc public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc
public class DDRUMActionEventSession: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    @objc public var id: String {
        root.swiftModel.session.id
    }

    @objc public var type: DDRUMActionEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMActionEventSessionRUMSessionType: Int {
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

@objc
public enum DDRUMActionEventSource: Int {
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
}

@objc
public class DDRUMActionEventRUMSyntheticsTest: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    @objc public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    @objc public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc
public class DDRUMActionEventRUMUser: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var email: String? {
        root.swiftModel.usr!.email
    }

    @objc public var id: String? {
        root.swiftModel.usr!.id
    }

    @objc public var name: String? {
        root.swiftModel.usr!.name
    }

    @objc public var usrInfo: [String: Any] {
        root.swiftModel.usr!.usrInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMActionEventView: NSObject {
    internal let root: DDRUMActionEvent

    internal init(root: DDRUMActionEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var inForeground: NSNumber? {
        root.swiftModel.view.inForeground as NSNumber?
    }

    @objc public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    @objc public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    @objc public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc
public class DDRUMErrorEvent: NSObject {
    internal var swiftModel: RUMErrorEvent
    internal var root: DDRUMErrorEvent { self }

    internal init(swiftModel: RUMErrorEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDRUMErrorEventDD {
        DDRUMErrorEventDD(root: root)
    }

    @objc public var action: DDRUMErrorEventAction? {
        root.swiftModel.action != nil ? DDRUMErrorEventAction(root: root) : nil
    }

    @objc public var application: DDRUMErrorEventApplication {
        DDRUMErrorEventApplication(root: root)
    }

    @objc public var buildId: String? {
        root.swiftModel.buildId
    }

    @objc public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    @objc public var ciTest: DDRUMErrorEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMErrorEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMErrorEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMErrorEventRUMConnectivity(root: root) : nil
    }

    @objc public var container: DDRUMErrorEventContainer? {
        root.swiftModel.container != nil ? DDRUMErrorEventContainer(root: root) : nil
    }

    @objc public var context: DDRUMErrorEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMErrorEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var device: DDRUMErrorEventRUMDevice? {
        root.swiftModel.device != nil ? DDRUMErrorEventRUMDevice(root: root) : nil
    }

    @objc public var display: DDRUMErrorEventDisplay? {
        root.swiftModel.display != nil ? DDRUMErrorEventDisplay(root: root) : nil
    }

    @objc public var error: DDRUMErrorEventError {
        DDRUMErrorEventError(root: root)
    }

    @objc public var featureFlags: DDRUMErrorEventFeatureFlags? {
        root.swiftModel.featureFlags != nil ? DDRUMErrorEventFeatureFlags(root: root) : nil
    }

    @objc public var freeze: DDRUMErrorEventFreeze? {
        root.swiftModel.freeze != nil ? DDRUMErrorEventFreeze(root: root) : nil
    }

    @objc public var os: DDRUMErrorEventRUMOperatingSystem? {
        root.swiftModel.os != nil ? DDRUMErrorEventRUMOperatingSystem(root: root) : nil
    }

    @objc public var service: String? {
        root.swiftModel.service
    }

    @objc public var session: DDRUMErrorEventSession {
        DDRUMErrorEventSession(root: root)
    }

    @objc public var source: DDRUMErrorEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var synthetics: DDRUMErrorEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? DDRUMErrorEventRUMSyntheticsTest(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var usr: DDRUMErrorEventRUMUser? {
        root.swiftModel.usr != nil ? DDRUMErrorEventRUMUser(root: root) : nil
    }

    @objc public var version: String? {
        root.swiftModel.version
    }

    @objc public var view: DDRUMErrorEventView {
        DDRUMErrorEventView(root: root)
    }
}

@objc
public class DDRUMErrorEventDD: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var configuration: DDRUMErrorEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? DDRUMErrorEventDDConfiguration(root: root) : nil
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMErrorEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMErrorEventDDSession(root: root) : nil
    }
}

@objc
public class DDRUMErrorEventDDConfiguration: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    @objc public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc
public class DDRUMErrorEventDDSession: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMErrorEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    @objc public var sessionPrecondition: DDRUMErrorEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc
public enum DDRUMErrorEventDDSessionPlan: Int {
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

@objc
public enum DDRUMErrorEventDDSessionRUMSessionPrecondition: Int {
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

@objc
public class DDRUMErrorEventAction: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var id: DDRUMErrorEventActionRUMActionID {
        DDRUMErrorEventActionRUMActionID(root: root)
    }
}

@objc
public class DDRUMErrorEventActionRUMActionID: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var string: String? {
        guard case .string(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }

    @objc public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }
}

@objc
public class DDRUMErrorEventApplication: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application.id
    }
}

@objc
public class DDRUMErrorEventRUMCITest: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc
public class DDRUMErrorEventRUMConnectivity: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var cellular: DDRUMErrorEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? DDRUMErrorEventRUMConnectivityCellular(root: root) : nil
    }

    @objc public var effectiveType: DDRUMErrorEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    @objc public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { DDRUMErrorEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    @objc public var status: DDRUMErrorEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc
public class DDRUMErrorEventRUMConnectivityCellular: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    @objc public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc
public enum DDRUMErrorEventRUMConnectivityEffectiveType: Int {
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

@objc
public enum DDRUMErrorEventRUMConnectivityInterfaces: Int {
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

@objc
public enum DDRUMErrorEventRUMConnectivityStatus: Int {
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

@objc
public class DDRUMErrorEventContainer: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var source: DDRUMErrorEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    @objc public var view: DDRUMErrorEventContainerView {
        DDRUMErrorEventContainerView(root: root)
    }
}

@objc
public enum DDRUMErrorEventContainerSource: Int {
    internal init(swift: RUMErrorEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
}

@objc
public class DDRUMErrorEventContainerView: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc
public class DDRUMErrorEventRUMEventAttributes: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var contextInfo: [String: Any] {
        root.swiftModel.context!.contextInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMErrorEventRUMDevice: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.device!.model
    }

    @objc public var name: String? {
        root.swiftModel.device!.name
    }

    @objc public var type: DDRUMErrorEventRUMDeviceRUMDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc
public enum DDRUMErrorEventRUMDeviceRUMDeviceType: Int {
    internal init(swift: RUMDevice.RUMDeviceType) {
        switch swift {
        case .mobile: self = .mobile
        case .desktop: self = .desktop
        case .tablet: self = .tablet
        case .tv: self = .tv
        case .gamingConsole: self = .gamingConsole
        case .bot: self = .bot
        case .other: self = .other
        }
    }

    internal var toSwift: RUMDevice.RUMDeviceType {
        switch self {
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc
public class DDRUMErrorEventDisplay: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var viewport: DDRUMErrorEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? DDRUMErrorEventDisplayViewport(root: root) : nil
    }
}

@objc
public class DDRUMErrorEventDisplayViewport: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    @objc public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc
public class DDRUMErrorEventError: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var binaryImages: [DDRUMErrorEventErrorBinaryImages]? {
        root.swiftModel.error.binaryImages?.map { DDRUMErrorEventErrorBinaryImages(swiftModel: $0) }
    }

    @objc public var category: DDRUMErrorEventErrorCategory {
        .init(swift: root.swiftModel.error.category)
    }

    @objc public var causes: [DDRUMErrorEventErrorCauses]? {
        set { root.swiftModel.error.causes = newValue?.map { $0.swiftModel } }
        get { root.swiftModel.error.causes?.map { DDRUMErrorEventErrorCauses(swiftModel: $0) } }
    }

    @objc public var csp: DDRUMErrorEventErrorCSP? {
        root.swiftModel.error.csp != nil ? DDRUMErrorEventErrorCSP(root: root) : nil
    }

    @objc public var fingerprint: String? {
        set { root.swiftModel.error.fingerprint = newValue }
        get { root.swiftModel.error.fingerprint }
    }

    @objc public var handling: DDRUMErrorEventErrorHandling {
        .init(swift: root.swiftModel.error.handling)
    }

    @objc public var handlingStack: String? {
        root.swiftModel.error.handlingStack
    }

    @objc public var id: String? {
        root.swiftModel.error.id
    }

    @objc public var isCrash: NSNumber? {
        root.swiftModel.error.isCrash as NSNumber?
    }

    @objc public var message: String {
        set { root.swiftModel.error.message = newValue }
        get { root.swiftModel.error.message }
    }

    @objc public var meta: DDRUMErrorEventErrorMeta? {
        root.swiftModel.error.meta != nil ? DDRUMErrorEventErrorMeta(root: root) : nil
    }

    @objc public var resource: DDRUMErrorEventErrorResource? {
        root.swiftModel.error.resource != nil ? DDRUMErrorEventErrorResource(root: root) : nil
    }

    @objc public var source: DDRUMErrorEventErrorSource {
        .init(swift: root.swiftModel.error.source)
    }

    @objc public var sourceType: DDRUMErrorEventErrorSourceType {
        .init(swift: root.swiftModel.error.sourceType)
    }

    @objc public var stack: String? {
        set { root.swiftModel.error.stack = newValue }
        get { root.swiftModel.error.stack }
    }

    @objc public var threads: [DDRUMErrorEventErrorThreads]? {
        root.swiftModel.error.threads?.map { DDRUMErrorEventErrorThreads(swiftModel: $0) }
    }

    @objc public var timeSinceAppStart: NSNumber? {
        root.swiftModel.error.timeSinceAppStart as NSNumber?
    }

    @objc public var type: String? {
        root.swiftModel.error.type
    }

    @objc public var wasTruncated: NSNumber? {
        root.swiftModel.error.wasTruncated as NSNumber?
    }
}

@objc
public class DDRUMErrorEventErrorBinaryImages: NSObject {
    internal var swiftModel: RUMErrorEvent.Error.BinaryImages
    internal var root: DDRUMErrorEventErrorBinaryImages { self }

    internal init(swiftModel: RUMErrorEvent.Error.BinaryImages) {
        self.swiftModel = swiftModel
    }

    @objc public var arch: String? {
        root.swiftModel.arch
    }

    @objc public var isSystem: NSNumber {
        root.swiftModel.isSystem as NSNumber
    }

    @objc public var loadAddress: String? {
        root.swiftModel.loadAddress
    }

    @objc public var maxAddress: String? {
        root.swiftModel.maxAddress
    }

    @objc public var name: String {
        root.swiftModel.name
    }

    @objc public var uuid: String {
        root.swiftModel.uuid
    }
}

@objc
public enum DDRUMErrorEventErrorCategory: Int {
    internal init(swift: RUMErrorEvent.Error.Category?) {
        switch swift {
        case nil: self = .none
        case .aNR?: self = .aNR
        case .appHang?: self = .appHang
        case .exception?: self = .exception
        }
    }

    internal var toSwift: RUMErrorEvent.Error.Category? {
        switch self {
        case .none: return nil
        case .aNR: return .aNR
        case .appHang: return .appHang
        case .exception: return .exception
        }
    }

    case none
    case aNR
    case appHang
    case exception
}

@objc
public class DDRUMErrorEventErrorCauses: NSObject {
    internal var swiftModel: RUMErrorEvent.Error.Causes
    internal var root: DDRUMErrorEventErrorCauses { self }

    internal init(swiftModel: RUMErrorEvent.Error.Causes) {
        self.swiftModel = swiftModel
    }

    @objc public var message: String {
        set { root.swiftModel.message = newValue }
        get { root.swiftModel.message }
    }

    @objc public var source: DDRUMErrorEventErrorCausesSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var stack: String? {
        set { root.swiftModel.stack = newValue }
        get { root.swiftModel.stack }
    }

    @objc public var type: String? {
        root.swiftModel.type
    }
}

@objc
public enum DDRUMErrorEventErrorCausesSource: Int {
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

@objc
public class DDRUMErrorEventErrorCSP: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var disposition: DDRUMErrorEventErrorCSPDisposition {
        .init(swift: root.swiftModel.error.csp!.disposition)
    }
}

@objc
public enum DDRUMErrorEventErrorCSPDisposition: Int {
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

@objc
public enum DDRUMErrorEventErrorHandling: Int {
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

@objc
public class DDRUMErrorEventErrorMeta: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var codeType: String? {
        root.swiftModel.error.meta!.codeType
    }

    @objc public var exceptionCodes: String? {
        root.swiftModel.error.meta!.exceptionCodes
    }

    @objc public var exceptionType: String? {
        root.swiftModel.error.meta!.exceptionType
    }

    @objc public var incidentIdentifier: String? {
        root.swiftModel.error.meta!.incidentIdentifier
    }

    @objc public var parentProcess: String? {
        root.swiftModel.error.meta!.parentProcess
    }

    @objc public var path: String? {
        root.swiftModel.error.meta!.path
    }

    @objc public var process: String? {
        root.swiftModel.error.meta!.process
    }
}

@objc
public class DDRUMErrorEventErrorResource: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var method: DDRUMErrorEventErrorResourceRUMMethod {
        .init(swift: root.swiftModel.error.resource!.method)
    }

    @objc public var provider: DDRUMErrorEventErrorResourceProvider? {
        root.swiftModel.error.resource!.provider != nil ? DDRUMErrorEventErrorResourceProvider(root: root) : nil
    }

    @objc public var statusCode: NSNumber {
        root.swiftModel.error.resource!.statusCode as NSNumber
    }

    @objc public var url: String {
        set { root.swiftModel.error.resource!.url = newValue }
        get { root.swiftModel.error.resource!.url }
    }
}

@objc
public enum DDRUMErrorEventErrorResourceRUMMethod: Int {
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

@objc
public class DDRUMErrorEventErrorResourceProvider: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var domain: String? {
        root.swiftModel.error.resource!.provider!.domain
    }

    @objc public var name: String? {
        root.swiftModel.error.resource!.provider!.name
    }

    @objc public var type: DDRUMErrorEventErrorResourceProviderProviderType {
        .init(swift: root.swiftModel.error.resource!.provider!.type)
    }
}

@objc
public enum DDRUMErrorEventErrorResourceProviderProviderType: Int {
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

@objc
public enum DDRUMErrorEventErrorSource: Int {
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

@objc
public enum DDRUMErrorEventErrorSourceType: Int {
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

@objc
public class DDRUMErrorEventErrorThreads: NSObject {
    internal var swiftModel: RUMErrorEvent.Error.Threads
    internal var root: DDRUMErrorEventErrorThreads { self }

    internal init(swiftModel: RUMErrorEvent.Error.Threads) {
        self.swiftModel = swiftModel
    }

    @objc public var crashed: NSNumber {
        root.swiftModel.crashed as NSNumber
    }

    @objc public var name: String {
        root.swiftModel.name
    }

    @objc public var stack: String {
        root.swiftModel.stack
    }

    @objc public var state: String? {
        root.swiftModel.state
    }
}

@objc
public class DDRUMErrorEventFeatureFlags: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var featureFlagsInfo: [String: Any] {
        root.swiftModel.featureFlags!.featureFlagsInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMErrorEventFreeze: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.freeze!.duration as NSNumber
    }
}

@objc
public class DDRUMErrorEventRUMOperatingSystem: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.os!.build
    }

    @objc public var name: String {
        root.swiftModel.os!.name
    }

    @objc public var version: String {
        root.swiftModel.os!.version
    }

    @objc public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc
public class DDRUMErrorEventSession: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    @objc public var id: String {
        root.swiftModel.session.id
    }

    @objc public var type: DDRUMErrorEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMErrorEventSessionRUMSessionType: Int {
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

@objc
public enum DDRUMErrorEventSource: Int {
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
}

@objc
public class DDRUMErrorEventRUMSyntheticsTest: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    @objc public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    @objc public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc
public class DDRUMErrorEventRUMUser: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var email: String? {
        root.swiftModel.usr!.email
    }

    @objc public var id: String? {
        root.swiftModel.usr!.id
    }

    @objc public var name: String? {
        root.swiftModel.usr!.name
    }

    @objc public var usrInfo: [String: Any] {
        root.swiftModel.usr!.usrInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMErrorEventView: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var inForeground: NSNumber? {
        root.swiftModel.view.inForeground as NSNumber?
    }

    @objc public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    @objc public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    @objc public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc
public class DDRUMLongTaskEvent: NSObject {
    internal var swiftModel: RUMLongTaskEvent
    internal var root: DDRUMLongTaskEvent { self }

    internal init(swiftModel: RUMLongTaskEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDRUMLongTaskEventDD {
        DDRUMLongTaskEventDD(root: root)
    }

    @objc public var action: DDRUMLongTaskEventAction? {
        root.swiftModel.action != nil ? DDRUMLongTaskEventAction(root: root) : nil
    }

    @objc public var application: DDRUMLongTaskEventApplication {
        DDRUMLongTaskEventApplication(root: root)
    }

    @objc public var buildId: String? {
        root.swiftModel.buildId
    }

    @objc public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    @objc public var ciTest: DDRUMLongTaskEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMLongTaskEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMLongTaskEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMLongTaskEventRUMConnectivity(root: root) : nil
    }

    @objc public var container: DDRUMLongTaskEventContainer? {
        root.swiftModel.container != nil ? DDRUMLongTaskEventContainer(root: root) : nil
    }

    @objc public var context: DDRUMLongTaskEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMLongTaskEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var device: DDRUMLongTaskEventRUMDevice? {
        root.swiftModel.device != nil ? DDRUMLongTaskEventRUMDevice(root: root) : nil
    }

    @objc public var display: DDRUMLongTaskEventDisplay? {
        root.swiftModel.display != nil ? DDRUMLongTaskEventDisplay(root: root) : nil
    }

    @objc public var longTask: DDRUMLongTaskEventLongTask {
        DDRUMLongTaskEventLongTask(root: root)
    }

    @objc public var os: DDRUMLongTaskEventRUMOperatingSystem? {
        root.swiftModel.os != nil ? DDRUMLongTaskEventRUMOperatingSystem(root: root) : nil
    }

    @objc public var service: String? {
        root.swiftModel.service
    }

    @objc public var session: DDRUMLongTaskEventSession {
        DDRUMLongTaskEventSession(root: root)
    }

    @objc public var source: DDRUMLongTaskEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var synthetics: DDRUMLongTaskEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? DDRUMLongTaskEventRUMSyntheticsTest(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var usr: DDRUMLongTaskEventRUMUser? {
        root.swiftModel.usr != nil ? DDRUMLongTaskEventRUMUser(root: root) : nil
    }

    @objc public var version: String? {
        root.swiftModel.version
    }

    @objc public var view: DDRUMLongTaskEventView {
        DDRUMLongTaskEventView(root: root)
    }
}

@objc
public class DDRUMLongTaskEventDD: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var configuration: DDRUMLongTaskEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? DDRUMLongTaskEventDDConfiguration(root: root) : nil
    }

    @objc public var discarded: NSNumber? {
        root.swiftModel.dd.discarded as NSNumber?
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMLongTaskEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMLongTaskEventDDSession(root: root) : nil
    }
}

@objc
public class DDRUMLongTaskEventDDConfiguration: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    @objc public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc
public class DDRUMLongTaskEventDDSession: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMLongTaskEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    @objc public var sessionPrecondition: DDRUMLongTaskEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc
public enum DDRUMLongTaskEventDDSessionPlan: Int {
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

@objc
public enum DDRUMLongTaskEventDDSessionRUMSessionPrecondition: Int {
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

@objc
public class DDRUMLongTaskEventAction: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var id: DDRUMLongTaskEventActionRUMActionID {
        DDRUMLongTaskEventActionRUMActionID(root: root)
    }
}

@objc
public class DDRUMLongTaskEventActionRUMActionID: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var string: String? {
        guard case .string(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }

    @objc public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }
}

@objc
public class DDRUMLongTaskEventApplication: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application.id
    }
}

@objc
public class DDRUMLongTaskEventRUMCITest: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc
public class DDRUMLongTaskEventRUMConnectivity: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var cellular: DDRUMLongTaskEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? DDRUMLongTaskEventRUMConnectivityCellular(root: root) : nil
    }

    @objc public var effectiveType: DDRUMLongTaskEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    @objc public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { DDRUMLongTaskEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    @objc public var status: DDRUMLongTaskEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc
public class DDRUMLongTaskEventRUMConnectivityCellular: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    @objc public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc
public enum DDRUMLongTaskEventRUMConnectivityEffectiveType: Int {
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

@objc
public enum DDRUMLongTaskEventRUMConnectivityInterfaces: Int {
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

@objc
public enum DDRUMLongTaskEventRUMConnectivityStatus: Int {
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

@objc
public class DDRUMLongTaskEventContainer: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var source: DDRUMLongTaskEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    @objc public var view: DDRUMLongTaskEventContainerView {
        DDRUMLongTaskEventContainerView(root: root)
    }
}

@objc
public enum DDRUMLongTaskEventContainerSource: Int {
    internal init(swift: RUMLongTaskEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
}

@objc
public class DDRUMLongTaskEventContainerView: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc
public class DDRUMLongTaskEventRUMEventAttributes: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var contextInfo: [String: Any] {
        root.swiftModel.context!.contextInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMLongTaskEventRUMDevice: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.device!.model
    }

    @objc public var name: String? {
        root.swiftModel.device!.name
    }

    @objc public var type: DDRUMLongTaskEventRUMDeviceRUMDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc
public enum DDRUMLongTaskEventRUMDeviceRUMDeviceType: Int {
    internal init(swift: RUMDevice.RUMDeviceType) {
        switch swift {
        case .mobile: self = .mobile
        case .desktop: self = .desktop
        case .tablet: self = .tablet
        case .tv: self = .tv
        case .gamingConsole: self = .gamingConsole
        case .bot: self = .bot
        case .other: self = .other
        }
    }

    internal var toSwift: RUMDevice.RUMDeviceType {
        switch self {
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc
public class DDRUMLongTaskEventDisplay: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var viewport: DDRUMLongTaskEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? DDRUMLongTaskEventDisplayViewport(root: root) : nil
    }
}

@objc
public class DDRUMLongTaskEventDisplayViewport: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    @objc public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc
public class DDRUMLongTaskEventLongTask: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.longTask.duration as NSNumber
    }

    @objc public var id: String? {
        root.swiftModel.longTask.id
    }

    @objc public var isFrozenFrame: NSNumber? {
        root.swiftModel.longTask.isFrozenFrame as NSNumber?
    }
}

@objc
public class DDRUMLongTaskEventRUMOperatingSystem: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.os!.build
    }

    @objc public var name: String {
        root.swiftModel.os!.name
    }

    @objc public var version: String {
        root.swiftModel.os!.version
    }

    @objc public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc
public class DDRUMLongTaskEventSession: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    @objc public var id: String {
        root.swiftModel.session.id
    }

    @objc public var type: DDRUMLongTaskEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMLongTaskEventSessionRUMSessionType: Int {
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

@objc
public enum DDRUMLongTaskEventSource: Int {
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
}

@objc
public class DDRUMLongTaskEventRUMSyntheticsTest: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    @objc public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    @objc public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc
public class DDRUMLongTaskEventRUMUser: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var email: String? {
        root.swiftModel.usr!.email
    }

    @objc public var id: String? {
        root.swiftModel.usr!.id
    }

    @objc public var name: String? {
        root.swiftModel.usr!.name
    }

    @objc public var usrInfo: [String: Any] {
        root.swiftModel.usr!.usrInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMLongTaskEventView: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    @objc public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    @objc public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc
public class DDRUMResourceEvent: NSObject {
    internal var swiftModel: RUMResourceEvent
    internal var root: DDRUMResourceEvent { self }

    internal init(swiftModel: RUMResourceEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDRUMResourceEventDD {
        DDRUMResourceEventDD(root: root)
    }

    @objc public var action: DDRUMResourceEventAction? {
        root.swiftModel.action != nil ? DDRUMResourceEventAction(root: root) : nil
    }

    @objc public var application: DDRUMResourceEventApplication {
        DDRUMResourceEventApplication(root: root)
    }

    @objc public var buildId: String? {
        root.swiftModel.buildId
    }

    @objc public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    @objc public var ciTest: DDRUMResourceEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMResourceEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMResourceEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMResourceEventRUMConnectivity(root: root) : nil
    }

    @objc public var container: DDRUMResourceEventContainer? {
        root.swiftModel.container != nil ? DDRUMResourceEventContainer(root: root) : nil
    }

    @objc public var context: DDRUMResourceEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMResourceEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var device: DDRUMResourceEventRUMDevice? {
        root.swiftModel.device != nil ? DDRUMResourceEventRUMDevice(root: root) : nil
    }

    @objc public var display: DDRUMResourceEventDisplay? {
        root.swiftModel.display != nil ? DDRUMResourceEventDisplay(root: root) : nil
    }

    @objc public var os: DDRUMResourceEventRUMOperatingSystem? {
        root.swiftModel.os != nil ? DDRUMResourceEventRUMOperatingSystem(root: root) : nil
    }

    @objc public var resource: DDRUMResourceEventResource {
        DDRUMResourceEventResource(root: root)
    }

    @objc public var service: String? {
        root.swiftModel.service
    }

    @objc public var session: DDRUMResourceEventSession {
        DDRUMResourceEventSession(root: root)
    }

    @objc public var source: DDRUMResourceEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var synthetics: DDRUMResourceEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? DDRUMResourceEventRUMSyntheticsTest(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var usr: DDRUMResourceEventRUMUser? {
        root.swiftModel.usr != nil ? DDRUMResourceEventRUMUser(root: root) : nil
    }

    @objc public var version: String? {
        root.swiftModel.version
    }

    @objc public var view: DDRUMResourceEventView {
        DDRUMResourceEventView(root: root)
    }
}

@objc
public class DDRUMResourceEventDD: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var configuration: DDRUMResourceEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? DDRUMResourceEventDDConfiguration(root: root) : nil
    }

    @objc public var discarded: NSNumber? {
        root.swiftModel.dd.discarded as NSNumber?
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var rulePsr: NSNumber? {
        root.swiftModel.dd.rulePsr as NSNumber?
    }

    @objc public var session: DDRUMResourceEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMResourceEventDDSession(root: root) : nil
    }

    @objc public var spanId: String? {
        root.swiftModel.dd.spanId
    }

    @objc public var traceId: String? {
        root.swiftModel.dd.traceId
    }
}

@objc
public class DDRUMResourceEventDDConfiguration: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    @objc public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc
public class DDRUMResourceEventDDSession: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMResourceEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    @objc public var sessionPrecondition: DDRUMResourceEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc
public enum DDRUMResourceEventDDSessionPlan: Int {
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

@objc
public enum DDRUMResourceEventDDSessionRUMSessionPrecondition: Int {
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

@objc
public class DDRUMResourceEventAction: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var id: DDRUMResourceEventActionRUMActionID {
        DDRUMResourceEventActionRUMActionID(root: root)
    }
}

@objc
public class DDRUMResourceEventActionRUMActionID: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var string: String? {
        guard case .string(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }

    @objc public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.action!.id else {
            return nil
        }
        return value
    }
}

@objc
public class DDRUMResourceEventApplication: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application.id
    }
}

@objc
public class DDRUMResourceEventRUMCITest: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc
public class DDRUMResourceEventRUMConnectivity: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var cellular: DDRUMResourceEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? DDRUMResourceEventRUMConnectivityCellular(root: root) : nil
    }

    @objc public var effectiveType: DDRUMResourceEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    @objc public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { DDRUMResourceEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    @objc public var status: DDRUMResourceEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc
public class DDRUMResourceEventRUMConnectivityCellular: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    @objc public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc
public enum DDRUMResourceEventRUMConnectivityEffectiveType: Int {
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

@objc
public enum DDRUMResourceEventRUMConnectivityInterfaces: Int {
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

@objc
public enum DDRUMResourceEventRUMConnectivityStatus: Int {
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

@objc
public class DDRUMResourceEventContainer: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var source: DDRUMResourceEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    @objc public var view: DDRUMResourceEventContainerView {
        DDRUMResourceEventContainerView(root: root)
    }
}

@objc
public enum DDRUMResourceEventContainerSource: Int {
    internal init(swift: RUMResourceEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
}

@objc
public class DDRUMResourceEventContainerView: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc
public class DDRUMResourceEventRUMEventAttributes: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var contextInfo: [String: Any] {
        root.swiftModel.context!.contextInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMResourceEventRUMDevice: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.device!.model
    }

    @objc public var name: String? {
        root.swiftModel.device!.name
    }

    @objc public var type: DDRUMResourceEventRUMDeviceRUMDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc
public enum DDRUMResourceEventRUMDeviceRUMDeviceType: Int {
    internal init(swift: RUMDevice.RUMDeviceType) {
        switch swift {
        case .mobile: self = .mobile
        case .desktop: self = .desktop
        case .tablet: self = .tablet
        case .tv: self = .tv
        case .gamingConsole: self = .gamingConsole
        case .bot: self = .bot
        case .other: self = .other
        }
    }

    internal var toSwift: RUMDevice.RUMDeviceType {
        switch self {
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc
public class DDRUMResourceEventDisplay: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var viewport: DDRUMResourceEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? DDRUMResourceEventDisplayViewport(root: root) : nil
    }
}

@objc
public class DDRUMResourceEventDisplayViewport: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    @objc public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc
public class DDRUMResourceEventRUMOperatingSystem: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.os!.build
    }

    @objc public var name: String {
        root.swiftModel.os!.name
    }

    @objc public var version: String {
        root.swiftModel.os!.version
    }

    @objc public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc
public class DDRUMResourceEventResource: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var connect: DDRUMResourceEventResourceConnect? {
        root.swiftModel.resource.connect != nil ? DDRUMResourceEventResourceConnect(root: root) : nil
    }

    @objc public var decodedBodySize: NSNumber? {
        root.swiftModel.resource.decodedBodySize as NSNumber?
    }

    @objc public var dns: DDRUMResourceEventResourceDNS? {
        root.swiftModel.resource.dns != nil ? DDRUMResourceEventResourceDNS(root: root) : nil
    }

    @objc public var download: DDRUMResourceEventResourceDownload? {
        root.swiftModel.resource.download != nil ? DDRUMResourceEventResourceDownload(root: root) : nil
    }

    @objc public var duration: NSNumber? {
        root.swiftModel.resource.duration as NSNumber?
    }

    @objc public var encodedBodySize: NSNumber? {
        root.swiftModel.resource.encodedBodySize as NSNumber?
    }

    @objc public var firstByte: DDRUMResourceEventResourceFirstByte? {
        root.swiftModel.resource.firstByte != nil ? DDRUMResourceEventResourceFirstByte(root: root) : nil
    }

    @objc public var graphql: DDRUMResourceEventResourceGraphql? {
        root.swiftModel.resource.graphql != nil ? DDRUMResourceEventResourceGraphql(root: root) : nil
    }

    @objc public var id: String? {
        root.swiftModel.resource.id
    }

    @objc public var method: DDRUMResourceEventResourceRUMMethod {
        .init(swift: root.swiftModel.resource.method)
    }

    @objc public var provider: DDRUMResourceEventResourceProvider? {
        root.swiftModel.resource.provider != nil ? DDRUMResourceEventResourceProvider(root: root) : nil
    }

    @objc public var redirect: DDRUMResourceEventResourceRedirect? {
        root.swiftModel.resource.redirect != nil ? DDRUMResourceEventResourceRedirect(root: root) : nil
    }

    @objc public var renderBlockingStatus: DDRUMResourceEventResourceRenderBlockingStatus {
        .init(swift: root.swiftModel.resource.renderBlockingStatus)
    }

    @objc public var size: NSNumber? {
        root.swiftModel.resource.size as NSNumber?
    }

    @objc public var ssl: DDRUMResourceEventResourceSSL? {
        root.swiftModel.resource.ssl != nil ? DDRUMResourceEventResourceSSL(root: root) : nil
    }

    @objc public var statusCode: NSNumber? {
        root.swiftModel.resource.statusCode as NSNumber?
    }

    @objc public var transferSize: NSNumber? {
        root.swiftModel.resource.transferSize as NSNumber?
    }

    @objc public var type: DDRUMResourceEventResourceResourceType {
        .init(swift: root.swiftModel.resource.type)
    }

    @objc public var url: String {
        set { root.swiftModel.resource.url = newValue }
        get { root.swiftModel.resource.url }
    }
}

@objc
public class DDRUMResourceEventResourceConnect: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.connect!.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.resource.connect!.start as NSNumber
    }
}

@objc
public class DDRUMResourceEventResourceDNS: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.dns!.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.resource.dns!.start as NSNumber
    }
}

@objc
public class DDRUMResourceEventResourceDownload: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.download!.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.resource.download!.start as NSNumber
    }
}

@objc
public class DDRUMResourceEventResourceFirstByte: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.firstByte!.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.resource.firstByte!.start as NSNumber
    }
}

@objc
public class DDRUMResourceEventResourceGraphql: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var operationName: String? {
        root.swiftModel.resource.graphql!.operationName
    }

    @objc public var operationType: DDRUMResourceEventResourceGraphqlOperationType {
        .init(swift: root.swiftModel.resource.graphql!.operationType)
    }

    @objc public var payload: String? {
        set { root.swiftModel.resource.graphql!.payload = newValue }
        get { root.swiftModel.resource.graphql!.payload }
    }

    @objc public var variables: String? {
        set { root.swiftModel.resource.graphql!.variables = newValue }
        get { root.swiftModel.resource.graphql!.variables }
    }
}

@objc
public enum DDRUMResourceEventResourceGraphqlOperationType: Int {
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

@objc
public enum DDRUMResourceEventResourceRUMMethod: Int {
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

@objc
public class DDRUMResourceEventResourceProvider: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var domain: String? {
        root.swiftModel.resource.provider!.domain
    }

    @objc public var name: String? {
        root.swiftModel.resource.provider!.name
    }

    @objc public var type: DDRUMResourceEventResourceProviderProviderType {
        .init(swift: root.swiftModel.resource.provider!.type)
    }
}

@objc
public enum DDRUMResourceEventResourceProviderProviderType: Int {
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

@objc
public class DDRUMResourceEventResourceRedirect: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.redirect!.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.resource.redirect!.start as NSNumber
    }
}

@objc
public enum DDRUMResourceEventResourceRenderBlockingStatus: Int {
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

@objc
public class DDRUMResourceEventResourceSSL: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.ssl!.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.resource.ssl!.start as NSNumber
    }
}

@objc
public enum DDRUMResourceEventResourceResourceType: Int {
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

@objc
public class DDRUMResourceEventSession: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    @objc public var id: String {
        root.swiftModel.session.id
    }

    @objc public var type: DDRUMResourceEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMResourceEventSessionRUMSessionType: Int {
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

@objc
public enum DDRUMResourceEventSource: Int {
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
}

@objc
public class DDRUMResourceEventRUMSyntheticsTest: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    @objc public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    @objc public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc
public class DDRUMResourceEventRUMUser: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var email: String? {
        root.swiftModel.usr!.email
    }

    @objc public var id: String? {
        root.swiftModel.usr!.id
    }

    @objc public var name: String? {
        root.swiftModel.usr!.name
    }

    @objc public var usrInfo: [String: Any] {
        root.swiftModel.usr!.usrInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMResourceEventView: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    @objc public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    @objc public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc
public class DDRUMViewEvent: NSObject {
    internal var swiftModel: RUMViewEvent
    internal var root: DDRUMViewEvent { self }

    internal init(swiftModel: RUMViewEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDRUMViewEventDD {
        DDRUMViewEventDD(root: root)
    }

    @objc public var application: DDRUMViewEventApplication {
        DDRUMViewEventApplication(root: root)
    }

    @objc public var buildId: String? {
        root.swiftModel.buildId
    }

    @objc public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    @objc public var ciTest: DDRUMViewEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMViewEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMViewEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMViewEventRUMConnectivity(root: root) : nil
    }

    @objc public var container: DDRUMViewEventContainer? {
        root.swiftModel.container != nil ? DDRUMViewEventContainer(root: root) : nil
    }

    @objc public var context: DDRUMViewEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMViewEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var device: DDRUMViewEventRUMDevice? {
        root.swiftModel.device != nil ? DDRUMViewEventRUMDevice(root: root) : nil
    }

    @objc public var display: DDRUMViewEventDisplay? {
        root.swiftModel.display != nil ? DDRUMViewEventDisplay(root: root) : nil
    }

    @objc public var featureFlags: DDRUMViewEventFeatureFlags? {
        root.swiftModel.featureFlags != nil ? DDRUMViewEventFeatureFlags(root: root) : nil
    }

    @objc public var os: DDRUMViewEventRUMOperatingSystem? {
        root.swiftModel.os != nil ? DDRUMViewEventRUMOperatingSystem(root: root) : nil
    }

    @objc public var privacy: DDRUMViewEventPrivacy? {
        root.swiftModel.privacy != nil ? DDRUMViewEventPrivacy(root: root) : nil
    }

    @objc public var service: String? {
        root.swiftModel.service
    }

    @objc public var session: DDRUMViewEventSession {
        DDRUMViewEventSession(root: root)
    }

    @objc public var source: DDRUMViewEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var synthetics: DDRUMViewEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? DDRUMViewEventRUMSyntheticsTest(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var usr: DDRUMViewEventRUMUser? {
        root.swiftModel.usr != nil ? DDRUMViewEventRUMUser(root: root) : nil
    }

    @objc public var version: String? {
        root.swiftModel.version
    }

    @objc public var view: DDRUMViewEventView {
        DDRUMViewEventView(root: root)
    }
}

@objc
public class DDRUMViewEventDD: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var configuration: DDRUMViewEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? DDRUMViewEventDDConfiguration(root: root) : nil
    }

    @objc public var documentVersion: NSNumber {
        root.swiftModel.dd.documentVersion as NSNumber
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var pageStates: [DDRUMViewEventDDPageStates]? {
        root.swiftModel.dd.pageStates?.map { DDRUMViewEventDDPageStates(swiftModel: $0) }
    }

    @objc public var replayStats: DDRUMViewEventDDReplayStats? {
        root.swiftModel.dd.replayStats != nil ? DDRUMViewEventDDReplayStats(root: root) : nil
    }

    @objc public var session: DDRUMViewEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMViewEventDDSession(root: root) : nil
    }
}

@objc
public class DDRUMViewEventDDConfiguration: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    @objc public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }

    @objc public var startSessionReplayRecordingManually: NSNumber? {
        root.swiftModel.dd.configuration!.startSessionReplayRecordingManually as NSNumber?
    }
}

@objc
public class DDRUMViewEventDDPageStates: NSObject {
    internal var swiftModel: RUMViewEvent.DD.PageStates
    internal var root: DDRUMViewEventDDPageStates { self }

    internal init(swiftModel: RUMViewEvent.DD.PageStates) {
        self.swiftModel = swiftModel
    }

    @objc public var start: NSNumber {
        root.swiftModel.start as NSNumber
    }

    @objc public var state: DDRUMViewEventDDPageStatesState {
        .init(swift: root.swiftModel.state)
    }
}

@objc
public enum DDRUMViewEventDDPageStatesState: Int {
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

@objc
public class DDRUMViewEventDDReplayStats: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var recordsCount: NSNumber? {
        root.swiftModel.dd.replayStats!.recordsCount as NSNumber?
    }

    @objc public var segmentsCount: NSNumber? {
        root.swiftModel.dd.replayStats!.segmentsCount as NSNumber?
    }

    @objc public var segmentsTotalRawSize: NSNumber? {
        root.swiftModel.dd.replayStats!.segmentsTotalRawSize as NSNumber?
    }
}

@objc
public class DDRUMViewEventDDSession: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMViewEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    @objc public var sessionPrecondition: DDRUMViewEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc
public enum DDRUMViewEventDDSessionPlan: Int {
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

@objc
public enum DDRUMViewEventDDSessionRUMSessionPrecondition: Int {
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

@objc
public class DDRUMViewEventApplication: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application.id
    }
}

@objc
public class DDRUMViewEventRUMCITest: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc
public class DDRUMViewEventRUMConnectivity: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var cellular: DDRUMViewEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? DDRUMViewEventRUMConnectivityCellular(root: root) : nil
    }

    @objc public var effectiveType: DDRUMViewEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    @objc public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { DDRUMViewEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    @objc public var status: DDRUMViewEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc
public class DDRUMViewEventRUMConnectivityCellular: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    @objc public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc
public enum DDRUMViewEventRUMConnectivityEffectiveType: Int {
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

@objc
public enum DDRUMViewEventRUMConnectivityInterfaces: Int {
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

@objc
public enum DDRUMViewEventRUMConnectivityStatus: Int {
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

@objc
public class DDRUMViewEventContainer: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var source: DDRUMViewEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    @objc public var view: DDRUMViewEventContainerView {
        DDRUMViewEventContainerView(root: root)
    }
}

@objc
public enum DDRUMViewEventContainerSource: Int {
    internal init(swift: RUMViewEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
}

@objc
public class DDRUMViewEventContainerView: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc
public class DDRUMViewEventRUMEventAttributes: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var contextInfo: [String: Any] {
        root.swiftModel.context!.contextInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMViewEventRUMDevice: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.device!.model
    }

    @objc public var name: String? {
        root.swiftModel.device!.name
    }

    @objc public var type: DDRUMViewEventRUMDeviceRUMDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc
public enum DDRUMViewEventRUMDeviceRUMDeviceType: Int {
    internal init(swift: RUMDevice.RUMDeviceType) {
        switch swift {
        case .mobile: self = .mobile
        case .desktop: self = .desktop
        case .tablet: self = .tablet
        case .tv: self = .tv
        case .gamingConsole: self = .gamingConsole
        case .bot: self = .bot
        case .other: self = .other
        }
    }

    internal var toSwift: RUMDevice.RUMDeviceType {
        switch self {
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc
public class DDRUMViewEventDisplay: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var scroll: DDRUMViewEventDisplayScroll? {
        root.swiftModel.display!.scroll != nil ? DDRUMViewEventDisplayScroll(root: root) : nil
    }

    @objc public var viewport: DDRUMViewEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? DDRUMViewEventDisplayViewport(root: root) : nil
    }
}

@objc
public class DDRUMViewEventDisplayScroll: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var maxDepth: NSNumber {
        root.swiftModel.display!.scroll!.maxDepth as NSNumber
    }

    @objc public var maxDepthScrollTop: NSNumber {
        root.swiftModel.display!.scroll!.maxDepthScrollTop as NSNumber
    }

    @objc public var maxScrollHeight: NSNumber {
        root.swiftModel.display!.scroll!.maxScrollHeight as NSNumber
    }

    @objc public var maxScrollHeightTime: NSNumber {
        root.swiftModel.display!.scroll!.maxScrollHeightTime as NSNumber
    }
}

@objc
public class DDRUMViewEventDisplayViewport: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    @objc public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc
public class DDRUMViewEventFeatureFlags: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var featureFlagsInfo: [String: Any] {
        root.swiftModel.featureFlags!.featureFlagsInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMViewEventRUMOperatingSystem: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.os!.build
    }

    @objc public var name: String {
        root.swiftModel.os!.name
    }

    @objc public var version: String {
        root.swiftModel.os!.version
    }

    @objc public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc
public class DDRUMViewEventPrivacy: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var replayLevel: DDRUMViewEventPrivacyReplayLevel {
        .init(swift: root.swiftModel.privacy!.replayLevel)
    }
}

@objc
public enum DDRUMViewEventPrivacyReplayLevel: Int {
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

@objc
public class DDRUMViewEventSession: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    @objc public var id: String {
        root.swiftModel.session.id
    }

    @objc public var isActive: NSNumber? {
        root.swiftModel.session.isActive as NSNumber?
    }

    @objc public var sampledForReplay: NSNumber? {
        root.swiftModel.session.sampledForReplay as NSNumber?
    }

    @objc public var type: DDRUMViewEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMViewEventSessionRUMSessionType: Int {
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

@objc
public enum DDRUMViewEventSource: Int {
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
}

@objc
public class DDRUMViewEventRUMSyntheticsTest: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    @objc public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    @objc public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc
public class DDRUMViewEventRUMUser: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var email: String? {
        root.swiftModel.usr!.email
    }

    @objc public var id: String? {
        root.swiftModel.usr!.id
    }

    @objc public var name: String? {
        root.swiftModel.usr!.name
    }

    @objc public var usrInfo: [String: Any] {
        root.swiftModel.usr!.usrInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMViewEventView: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var action: DDRUMViewEventViewAction {
        DDRUMViewEventViewAction(root: root)
    }

    @objc public var cpuTicksCount: NSNumber? {
        root.swiftModel.view.cpuTicksCount as NSNumber?
    }

    @objc public var cpuTicksPerSecond: NSNumber? {
        root.swiftModel.view.cpuTicksPerSecond as NSNumber?
    }

    @objc public var crash: DDRUMViewEventViewCrash? {
        root.swiftModel.view.crash != nil ? DDRUMViewEventViewCrash(root: root) : nil
    }

    @objc public var cumulativeLayoutShift: NSNumber? {
        root.swiftModel.view.cumulativeLayoutShift as NSNumber?
    }

    @objc public var cumulativeLayoutShiftTargetSelector: String? {
        root.swiftModel.view.cumulativeLayoutShiftTargetSelector
    }

    @objc public var cumulativeLayoutShiftTime: NSNumber? {
        root.swiftModel.view.cumulativeLayoutShiftTime as NSNumber?
    }

    @objc public var customTimings: [String: NSNumber]? {
        root.swiftModel.view.customTimings as [String: NSNumber]?
    }

    @objc public var domComplete: NSNumber? {
        root.swiftModel.view.domComplete as NSNumber?
    }

    @objc public var domContentLoaded: NSNumber? {
        root.swiftModel.view.domContentLoaded as NSNumber?
    }

    @objc public var domInteractive: NSNumber? {
        root.swiftModel.view.domInteractive as NSNumber?
    }

    @objc public var error: DDRUMViewEventViewError {
        DDRUMViewEventViewError(root: root)
    }

    @objc public var firstByte: NSNumber? {
        root.swiftModel.view.firstByte as NSNumber?
    }

    @objc public var firstContentfulPaint: NSNumber? {
        root.swiftModel.view.firstContentfulPaint as NSNumber?
    }

    @objc public var firstInputDelay: NSNumber? {
        root.swiftModel.view.firstInputDelay as NSNumber?
    }

    @objc public var firstInputTargetSelector: String? {
        root.swiftModel.view.firstInputTargetSelector
    }

    @objc public var firstInputTime: NSNumber? {
        root.swiftModel.view.firstInputTime as NSNumber?
    }

    @objc public var flutterBuildTime: DDRUMViewEventViewFlutterBuildTime? {
        root.swiftModel.view.flutterBuildTime != nil ? DDRUMViewEventViewFlutterBuildTime(root: root) : nil
    }

    @objc public var flutterRasterTime: DDRUMViewEventViewFlutterRasterTime? {
        root.swiftModel.view.flutterRasterTime != nil ? DDRUMViewEventViewFlutterRasterTime(root: root) : nil
    }

    @objc public var frozenFrame: DDRUMViewEventViewFrozenFrame? {
        root.swiftModel.view.frozenFrame != nil ? DDRUMViewEventViewFrozenFrame(root: root) : nil
    }

    @objc public var frustration: DDRUMViewEventViewFrustration? {
        root.swiftModel.view.frustration != nil ? DDRUMViewEventViewFrustration(root: root) : nil
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var inForegroundPeriods: [DDRUMViewEventViewInForegroundPeriods]? {
        root.swiftModel.view.inForegroundPeriods?.map { DDRUMViewEventViewInForegroundPeriods(swiftModel: $0) }
    }

    @objc public var interactionToNextPaint: NSNumber? {
        root.swiftModel.view.interactionToNextPaint as NSNumber?
    }

    @objc public var interactionToNextPaintTargetSelector: String? {
        root.swiftModel.view.interactionToNextPaintTargetSelector
    }

    @objc public var interactionToNextPaintTime: NSNumber? {
        root.swiftModel.view.interactionToNextPaintTime as NSNumber?
    }

    @objc public var isActive: NSNumber? {
        root.swiftModel.view.isActive as NSNumber?
    }

    @objc public var isSlowRendered: NSNumber? {
        root.swiftModel.view.isSlowRendered as NSNumber?
    }

    @objc public var jsRefreshRate: DDRUMViewEventViewJsRefreshRate? {
        root.swiftModel.view.jsRefreshRate != nil ? DDRUMViewEventViewJsRefreshRate(root: root) : nil
    }

    @objc public var largestContentfulPaint: NSNumber? {
        root.swiftModel.view.largestContentfulPaint as NSNumber?
    }

    @objc public var largestContentfulPaintTargetSelector: String? {
        root.swiftModel.view.largestContentfulPaintTargetSelector
    }

    @objc public var loadEvent: NSNumber? {
        root.swiftModel.view.loadEvent as NSNumber?
    }

    @objc public var loadingTime: NSNumber? {
        root.swiftModel.view.loadingTime as NSNumber?
    }

    @objc public var loadingType: DDRUMViewEventViewLoadingType {
        .init(swift: root.swiftModel.view.loadingType)
    }

    @objc public var longTask: DDRUMViewEventViewLongTask? {
        root.swiftModel.view.longTask != nil ? DDRUMViewEventViewLongTask(root: root) : nil
    }

    @objc public var memoryAverage: NSNumber? {
        root.swiftModel.view.memoryAverage as NSNumber?
    }

    @objc public var memoryMax: NSNumber? {
        root.swiftModel.view.memoryMax as NSNumber?
    }

    @objc public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    @objc public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    @objc public var refreshRateAverage: NSNumber? {
        root.swiftModel.view.refreshRateAverage as NSNumber?
    }

    @objc public var refreshRateMin: NSNumber? {
        root.swiftModel.view.refreshRateMin as NSNumber?
    }

    @objc public var resource: DDRUMViewEventViewResource {
        DDRUMViewEventViewResource(root: root)
    }

    @objc public var timeSpent: NSNumber {
        root.swiftModel.view.timeSpent as NSNumber
    }

    @objc public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc
public class DDRUMViewEventViewAction: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.action.count as NSNumber
    }
}

@objc
public class DDRUMViewEventViewCrash: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.crash!.count as NSNumber
    }
}

@objc
public class DDRUMViewEventViewError: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.error.count as NSNumber
    }
}

@objc
public class DDRUMViewEventViewFlutterBuildTime: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var average: NSNumber {
        root.swiftModel.view.flutterBuildTime!.average as NSNumber
    }

    @objc public var max: NSNumber {
        root.swiftModel.view.flutterBuildTime!.max as NSNumber
    }

    @objc public var metricMax: NSNumber? {
        root.swiftModel.view.flutterBuildTime!.metricMax as NSNumber?
    }

    @objc public var min: NSNumber {
        root.swiftModel.view.flutterBuildTime!.min as NSNumber
    }
}

@objc
public class DDRUMViewEventViewFlutterRasterTime: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var average: NSNumber {
        root.swiftModel.view.flutterRasterTime!.average as NSNumber
    }

    @objc public var max: NSNumber {
        root.swiftModel.view.flutterRasterTime!.max as NSNumber
    }

    @objc public var metricMax: NSNumber? {
        root.swiftModel.view.flutterRasterTime!.metricMax as NSNumber?
    }

    @objc public var min: NSNumber {
        root.swiftModel.view.flutterRasterTime!.min as NSNumber
    }
}

@objc
public class DDRUMViewEventViewFrozenFrame: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.frozenFrame!.count as NSNumber
    }
}

@objc
public class DDRUMViewEventViewFrustration: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.frustration!.count as NSNumber
    }
}

@objc
public class DDRUMViewEventViewInForegroundPeriods: NSObject {
    internal var swiftModel: RUMViewEvent.View.InForegroundPeriods
    internal var root: DDRUMViewEventViewInForegroundPeriods { self }

    internal init(swiftModel: RUMViewEvent.View.InForegroundPeriods) {
        self.swiftModel = swiftModel
    }

    @objc public var duration: NSNumber {
        root.swiftModel.duration as NSNumber
    }

    @objc public var start: NSNumber {
        root.swiftModel.start as NSNumber
    }
}

@objc
public class DDRUMViewEventViewJsRefreshRate: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var average: NSNumber {
        root.swiftModel.view.jsRefreshRate!.average as NSNumber
    }

    @objc public var max: NSNumber {
        root.swiftModel.view.jsRefreshRate!.max as NSNumber
    }

    @objc public var metricMax: NSNumber? {
        root.swiftModel.view.jsRefreshRate!.metricMax as NSNumber?
    }

    @objc public var min: NSNumber {
        root.swiftModel.view.jsRefreshRate!.min as NSNumber
    }
}

@objc
public enum DDRUMViewEventViewLoadingType: Int {
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

@objc
public class DDRUMViewEventViewLongTask: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.longTask!.count as NSNumber
    }
}

@objc
public class DDRUMViewEventViewResource: NSObject {
    internal let root: DDRUMViewEvent

    internal init(root: DDRUMViewEvent) {
        self.root = root
    }

    @objc public var count: NSNumber {
        root.swiftModel.view.resource.count as NSNumber
    }
}

@objc
public class DDRUMVitalEvent: NSObject {
    internal var swiftModel: RUMVitalEvent
    internal var root: DDRUMVitalEvent { self }

    internal init(swiftModel: RUMVitalEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDRUMVitalEventDD {
        DDRUMVitalEventDD(root: root)
    }

    @objc public var application: DDRUMVitalEventApplication {
        DDRUMVitalEventApplication(root: root)
    }

    @objc public var buildId: String? {
        root.swiftModel.buildId
    }

    @objc public var buildVersion: String? {
        root.swiftModel.buildVersion
    }

    @objc public var ciTest: DDRUMVitalEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMVitalEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMVitalEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMVitalEventRUMConnectivity(root: root) : nil
    }

    @objc public var container: DDRUMVitalEventContainer? {
        root.swiftModel.container != nil ? DDRUMVitalEventContainer(root: root) : nil
    }

    @objc public var context: DDRUMVitalEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMVitalEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var device: DDRUMVitalEventRUMDevice? {
        root.swiftModel.device != nil ? DDRUMVitalEventRUMDevice(root: root) : nil
    }

    @objc public var display: DDRUMVitalEventDisplay? {
        root.swiftModel.display != nil ? DDRUMVitalEventDisplay(root: root) : nil
    }

    @objc public var os: DDRUMVitalEventRUMOperatingSystem? {
        root.swiftModel.os != nil ? DDRUMVitalEventRUMOperatingSystem(root: root) : nil
    }

    @objc public var service: String? {
        root.swiftModel.service
    }

    @objc public var session: DDRUMVitalEventSession {
        DDRUMVitalEventSession(root: root)
    }

    @objc public var source: DDRUMVitalEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var synthetics: DDRUMVitalEventRUMSyntheticsTest? {
        root.swiftModel.synthetics != nil ? DDRUMVitalEventRUMSyntheticsTest(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var usr: DDRUMVitalEventRUMUser? {
        root.swiftModel.usr != nil ? DDRUMVitalEventRUMUser(root: root) : nil
    }

    @objc public var version: String? {
        root.swiftModel.version
    }

    @objc public var view: DDRUMVitalEventView {
        DDRUMVitalEventView(root: root)
    }

    @objc public var vital: DDRUMVitalEventVital {
        DDRUMVitalEventVital(root: root)
    }
}

@objc
public class DDRUMVitalEventDD: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var configuration: DDRUMVitalEventDDConfiguration? {
        root.swiftModel.dd.configuration != nil ? DDRUMVitalEventDDConfiguration(root: root) : nil
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMVitalEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMVitalEventDDSession(root: root) : nil
    }

    @objc public var vital: DDRUMVitalEventDDVital? {
        root.swiftModel.dd.vital != nil ? DDRUMVitalEventDDVital(root: root) : nil
    }
}

@objc
public class DDRUMVitalEventDDConfiguration: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        root.swiftModel.dd.configuration!.sessionReplaySampleRate as NSNumber?
    }

    @objc public var sessionSampleRate: NSNumber {
        root.swiftModel.dd.configuration!.sessionSampleRate as NSNumber
    }
}

@objc
public class DDRUMVitalEventDDSession: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMVitalEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }

    @objc public var sessionPrecondition: DDRUMVitalEventDDSessionRUMSessionPrecondition {
        .init(swift: root.swiftModel.dd.session!.sessionPrecondition)
    }
}

@objc
public enum DDRUMVitalEventDDSessionPlan: Int {
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

@objc
public enum DDRUMVitalEventDDSessionRUMSessionPrecondition: Int {
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

@objc
public class DDRUMVitalEventDDVital: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var computedValue: NSNumber? {
        root.swiftModel.dd.vital!.computedValue as NSNumber?
    }
}

@objc
public class DDRUMVitalEventApplication: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application.id
    }
}

@objc
public class DDRUMVitalEventRUMCITest: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var testExecutionId: String {
        root.swiftModel.ciTest!.testExecutionId
    }
}

@objc
public class DDRUMVitalEventRUMConnectivity: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var cellular: DDRUMVitalEventRUMConnectivityCellular? {
        root.swiftModel.connectivity!.cellular != nil ? DDRUMVitalEventRUMConnectivityCellular(root: root) : nil
    }

    @objc public var effectiveType: DDRUMVitalEventRUMConnectivityEffectiveType {
        .init(swift: root.swiftModel.connectivity!.effectiveType)
    }

    @objc public var interfaces: [Int]? {
        root.swiftModel.connectivity!.interfaces?.map { DDRUMVitalEventRUMConnectivityInterfaces(swift: $0).rawValue }
    }

    @objc public var status: DDRUMVitalEventRUMConnectivityStatus {
        .init(swift: root.swiftModel.connectivity!.status)
    }
}

@objc
public class DDRUMVitalEventRUMConnectivityCellular: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var carrierName: String? {
        root.swiftModel.connectivity!.cellular!.carrierName
    }

    @objc public var technology: String? {
        root.swiftModel.connectivity!.cellular!.technology
    }
}

@objc
public enum DDRUMVitalEventRUMConnectivityEffectiveType: Int {
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

@objc
public enum DDRUMVitalEventRUMConnectivityInterfaces: Int {
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

@objc
public enum DDRUMVitalEventRUMConnectivityStatus: Int {
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

@objc
public class DDRUMVitalEventContainer: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var source: DDRUMVitalEventContainerSource {
        .init(swift: root.swiftModel.container!.source)
    }

    @objc public var view: DDRUMVitalEventContainerView {
        DDRUMVitalEventContainerView(root: root)
    }
}

@objc
public enum DDRUMVitalEventContainerSource: Int {
    internal init(swift: RUMVitalEvent.Container.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .roku: self = .roku
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case roku
    case unity
}

@objc
public class DDRUMVitalEventContainerView: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.container!.view.id
    }
}

@objc
public class DDRUMVitalEventRUMEventAttributes: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var contextInfo: [String: Any] {
        root.swiftModel.context!.contextInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMVitalEventRUMDevice: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.device!.model
    }

    @objc public var name: String? {
        root.swiftModel.device!.name
    }

    @objc public var type: DDRUMVitalEventRUMDeviceRUMDeviceType {
        .init(swift: root.swiftModel.device!.type)
    }
}

@objc
public enum DDRUMVitalEventRUMDeviceRUMDeviceType: Int {
    internal init(swift: RUMDevice.RUMDeviceType) {
        switch swift {
        case .mobile: self = .mobile
        case .desktop: self = .desktop
        case .tablet: self = .tablet
        case .tv: self = .tv
        case .gamingConsole: self = .gamingConsole
        case .bot: self = .bot
        case .other: self = .other
        }
    }

    internal var toSwift: RUMDevice.RUMDeviceType {
        switch self {
        case .mobile: return .mobile
        case .desktop: return .desktop
        case .tablet: return .tablet
        case .tv: return .tv
        case .gamingConsole: return .gamingConsole
        case .bot: return .bot
        case .other: return .other
        }
    }

    case mobile
    case desktop
    case tablet
    case tv
    case gamingConsole
    case bot
    case other
}

@objc
public class DDRUMVitalEventDisplay: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var viewport: DDRUMVitalEventDisplayViewport? {
        root.swiftModel.display!.viewport != nil ? DDRUMVitalEventDisplayViewport(root: root) : nil
    }
}

@objc
public class DDRUMVitalEventDisplayViewport: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var height: NSNumber {
        root.swiftModel.display!.viewport!.height as NSNumber
    }

    @objc public var width: NSNumber {
        root.swiftModel.display!.viewport!.width as NSNumber
    }
}

@objc
public class DDRUMVitalEventRUMOperatingSystem: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.os!.build
    }

    @objc public var name: String {
        root.swiftModel.os!.name
    }

    @objc public var version: String {
        root.swiftModel.os!.version
    }

    @objc public var versionMajor: String {
        root.swiftModel.os!.versionMajor
    }
}

@objc
public class DDRUMVitalEventSession: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var hasReplay: NSNumber? {
        root.swiftModel.session.hasReplay as NSNumber?
    }

    @objc public var id: String {
        root.swiftModel.session.id
    }

    @objc public var type: DDRUMVitalEventSessionRUMSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMVitalEventSessionRUMSessionType: Int {
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

@objc
public enum DDRUMVitalEventSource: Int {
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
}

@objc
public class DDRUMVitalEventRUMSyntheticsTest: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var injected: NSNumber? {
        root.swiftModel.synthetics!.injected as NSNumber?
    }

    @objc public var resultId: String {
        root.swiftModel.synthetics!.resultId
    }

    @objc public var testId: String {
        root.swiftModel.synthetics!.testId
    }
}

@objc
public class DDRUMVitalEventRUMUser: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var email: String? {
        root.swiftModel.usr!.email
    }

    @objc public var id: String? {
        root.swiftModel.usr!.id
    }

    @objc public var name: String? {
        root.swiftModel.usr!.name
    }

    @objc public var usrInfo: [String: Any] {
        root.swiftModel.usr!.usrInfo.castToObjectiveC()
    }
}

@objc
public class DDRUMVitalEventView: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var name: String? {
        set { root.swiftModel.view.name = newValue }
        get { root.swiftModel.view.name }
    }

    @objc public var referrer: String? {
        set { root.swiftModel.view.referrer = newValue }
        get { root.swiftModel.view.referrer }
    }

    @objc public var url: String {
        set { root.swiftModel.view.url = newValue }
        get { root.swiftModel.view.url }
    }
}

@objc
public class DDRUMVitalEventVital: NSObject {
    internal let root: DDRUMVitalEvent

    internal init(root: DDRUMVitalEvent) {
        self.root = root
    }

    @objc public var custom: [String: NSNumber]? {
        root.swiftModel.vital.custom as [String: NSNumber]?
    }

    @objc public var id: String {
        root.swiftModel.vital.id
    }

    @objc public var name: String? {
        root.swiftModel.vital.name
    }

    @objc public var type: DDRUMVitalEventVitalVitalType {
        .init(swift: root.swiftModel.vital.type)
    }
}

@objc
public enum DDRUMVitalEventVitalVitalType: Int {
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

@objc
public class DDTelemetryErrorEvent: NSObject {
    internal var swiftModel: TelemetryErrorEvent
    internal var root: DDTelemetryErrorEvent { self }

    internal init(swiftModel: TelemetryErrorEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDTelemetryErrorEventDD {
        DDTelemetryErrorEventDD(root: root)
    }

    @objc public var action: DDTelemetryErrorEventAction? {
        root.swiftModel.action != nil ? DDTelemetryErrorEventAction(root: root) : nil
    }

    @objc public var application: DDTelemetryErrorEventApplication? {
        root.swiftModel.application != nil ? DDTelemetryErrorEventApplication(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var experimentalFeatures: [String]? {
        root.swiftModel.experimentalFeatures
    }

    @objc public var service: String {
        root.swiftModel.service
    }

    @objc public var session: DDTelemetryErrorEventSession? {
        root.swiftModel.session != nil ? DDTelemetryErrorEventSession(root: root) : nil
    }

    @objc public var source: DDTelemetryErrorEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var telemetry: DDTelemetryErrorEventTelemetry {
        DDTelemetryErrorEventTelemetry(root: root)
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var version: String {
        root.swiftModel.version
    }

    @objc public var view: DDTelemetryErrorEventView? {
        root.swiftModel.view != nil ? DDTelemetryErrorEventView(root: root) : nil
    }
}

@objc
public class DDTelemetryErrorEventDD: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }
}

@objc
public class DDTelemetryErrorEventAction: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.action!.id
    }
}

@objc
public class DDTelemetryErrorEventApplication: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application!.id
    }
}

@objc
public class DDTelemetryErrorEventSession: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.session!.id
    }
}

@objc
public enum DDTelemetryErrorEventSource: Int {
    internal init(swift: TelemetryErrorEvent.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case unity
}

@objc
public class DDTelemetryErrorEventTelemetry: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var device: DDTelemetryErrorEventTelemetryRUMTelemetryDevice? {
        root.swiftModel.telemetry.device != nil ? DDTelemetryErrorEventTelemetryRUMTelemetryDevice(root: root) : nil
    }

    @objc public var error: DDTelemetryErrorEventTelemetryError? {
        root.swiftModel.telemetry.error != nil ? DDTelemetryErrorEventTelemetryError(root: root) : nil
    }

    @objc public var message: String {
        root.swiftModel.telemetry.message
    }

    @objc public var os: DDTelemetryErrorEventTelemetryRUMTelemetryOperatingSystem? {
        root.swiftModel.telemetry.os != nil ? DDTelemetryErrorEventTelemetryRUMTelemetryOperatingSystem(root: root) : nil
    }

    @objc public var status: String {
        root.swiftModel.telemetry.status
    }

    @objc public var type: String? {
        root.swiftModel.telemetry.type
    }

    @objc public var telemetryInfo: [String: Any] {
        root.swiftModel.telemetry.telemetryInfo.castToObjectiveC()
    }
}

@objc
public class DDTelemetryErrorEventTelemetryRUMTelemetryDevice: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.telemetry.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.telemetry.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.telemetry.device!.model
    }
}

@objc
public class DDTelemetryErrorEventTelemetryError: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var kind: String? {
        root.swiftModel.telemetry.error!.kind
    }

    @objc public var stack: String? {
        root.swiftModel.telemetry.error!.stack
    }
}

@objc
public class DDTelemetryErrorEventTelemetryRUMTelemetryOperatingSystem: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.telemetry.os!.build
    }

    @objc public var name: String? {
        root.swiftModel.telemetry.os!.name
    }

    @objc public var version: String? {
        root.swiftModel.telemetry.os!.version
    }
}

@objc
public class DDTelemetryErrorEventView: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view!.id
    }
}

@objc
public class DDTelemetryDebugEvent: NSObject {
    internal var swiftModel: TelemetryDebugEvent
    internal var root: DDTelemetryDebugEvent { self }

    internal init(swiftModel: TelemetryDebugEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDTelemetryDebugEventDD {
        DDTelemetryDebugEventDD(root: root)
    }

    @objc public var action: DDTelemetryDebugEventAction? {
        root.swiftModel.action != nil ? DDTelemetryDebugEventAction(root: root) : nil
    }

    @objc public var application: DDTelemetryDebugEventApplication? {
        root.swiftModel.application != nil ? DDTelemetryDebugEventApplication(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var experimentalFeatures: [String]? {
        root.swiftModel.experimentalFeatures
    }

    @objc public var service: String {
        root.swiftModel.service
    }

    @objc public var session: DDTelemetryDebugEventSession? {
        root.swiftModel.session != nil ? DDTelemetryDebugEventSession(root: root) : nil
    }

    @objc public var source: DDTelemetryDebugEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var telemetry: DDTelemetryDebugEventTelemetry {
        DDTelemetryDebugEventTelemetry(root: root)
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var version: String {
        root.swiftModel.version
    }

    @objc public var view: DDTelemetryDebugEventView? {
        root.swiftModel.view != nil ? DDTelemetryDebugEventView(root: root) : nil
    }
}

@objc
public class DDTelemetryDebugEventDD: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }
}

@objc
public class DDTelemetryDebugEventAction: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.action!.id
    }
}

@objc
public class DDTelemetryDebugEventApplication: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application!.id
    }
}

@objc
public class DDTelemetryDebugEventSession: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.session!.id
    }
}

@objc
public enum DDTelemetryDebugEventSource: Int {
    internal init(swift: TelemetryDebugEvent.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case unity
}

@objc
public class DDTelemetryDebugEventTelemetry: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var device: DDTelemetryDebugEventTelemetryRUMTelemetryDevice? {
        root.swiftModel.telemetry.device != nil ? DDTelemetryDebugEventTelemetryRUMTelemetryDevice(root: root) : nil
    }

    @objc public var message: String {
        root.swiftModel.telemetry.message
    }

    @objc public var os: DDTelemetryDebugEventTelemetryRUMTelemetryOperatingSystem? {
        root.swiftModel.telemetry.os != nil ? DDTelemetryDebugEventTelemetryRUMTelemetryOperatingSystem(root: root) : nil
    }

    @objc public var status: String {
        root.swiftModel.telemetry.status
    }

    @objc public var type: String? {
        root.swiftModel.telemetry.type
    }

    @objc public var telemetryInfo: [String: Any] {
        root.swiftModel.telemetry.telemetryInfo.castToObjectiveC()
    }
}

@objc
public class DDTelemetryDebugEventTelemetryRUMTelemetryDevice: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.telemetry.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.telemetry.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.telemetry.device!.model
    }
}

@objc
public class DDTelemetryDebugEventTelemetryRUMTelemetryOperatingSystem: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.telemetry.os!.build
    }

    @objc public var name: String? {
        root.swiftModel.telemetry.os!.name
    }

    @objc public var version: String? {
        root.swiftModel.telemetry.os!.version
    }
}

@objc
public class DDTelemetryDebugEventView: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view!.id
    }
}

@objc
public class DDTelemetryConfigurationEvent: NSObject {
    internal var swiftModel: TelemetryConfigurationEvent
    internal var root: DDTelemetryConfigurationEvent { self }

    internal init(swiftModel: TelemetryConfigurationEvent) {
        self.swiftModel = swiftModel
    }

    @objc public var dd: DDTelemetryConfigurationEventDD {
        DDTelemetryConfigurationEventDD(root: root)
    }

    @objc public var action: DDTelemetryConfigurationEventAction? {
        root.swiftModel.action != nil ? DDTelemetryConfigurationEventAction(root: root) : nil
    }

    @objc public var application: DDTelemetryConfigurationEventApplication? {
        root.swiftModel.application != nil ? DDTelemetryConfigurationEventApplication(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var experimentalFeatures: [String]? {
        root.swiftModel.experimentalFeatures
    }

    @objc public var service: String {
        root.swiftModel.service
    }

    @objc public var session: DDTelemetryConfigurationEventSession? {
        root.swiftModel.session != nil ? DDTelemetryConfigurationEventSession(root: root) : nil
    }

    @objc public var source: DDTelemetryConfigurationEventSource {
        .init(swift: root.swiftModel.source)
    }

    @objc public var telemetry: DDTelemetryConfigurationEventTelemetry {
        DDTelemetryConfigurationEventTelemetry(root: root)
    }

    @objc public var type: String {
        root.swiftModel.type
    }

    @objc public var version: String {
        root.swiftModel.version
    }

    @objc public var view: DDTelemetryConfigurationEventView? {
        root.swiftModel.view != nil ? DDTelemetryConfigurationEventView(root: root) : nil
    }
}

@objc
public class DDTelemetryConfigurationEventDD: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }
}

@objc
public class DDTelemetryConfigurationEventAction: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.action!.id
    }
}

@objc
public class DDTelemetryConfigurationEventApplication: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.application!.id
    }
}

@objc
public class DDTelemetryConfigurationEventSession: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.session!.id
    }
}

@objc
public enum DDTelemetryConfigurationEventSource: Int {
    internal init(swift: TelemetryConfigurationEvent.Source) {
        switch swift {
        case .android: self = .android
        case .ios: self = .ios
        case .browser: self = .browser
        case .flutter: self = .flutter
        case .reactNative: self = .reactNative
        case .unity: self = .unity
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
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
    case unity
}

@objc
public class DDTelemetryConfigurationEventTelemetry: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var configuration: DDTelemetryConfigurationEventTelemetryConfiguration {
        DDTelemetryConfigurationEventTelemetryConfiguration(root: root)
    }

    @objc public var device: DDTelemetryConfigurationEventTelemetryRUMTelemetryDevice? {
        root.swiftModel.telemetry.device != nil ? DDTelemetryConfigurationEventTelemetryRUMTelemetryDevice(root: root) : nil
    }

    @objc public var os: DDTelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem? {
        root.swiftModel.telemetry.os != nil ? DDTelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem(root: root) : nil
    }

    @objc public var type: String {
        root.swiftModel.telemetry.type
    }

    @objc public var telemetryInfo: [String: Any] {
        root.swiftModel.telemetry.telemetryInfo.castToObjectiveC()
    }
}

@objc
public class DDTelemetryConfigurationEventTelemetryConfiguration: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var actionNameAttribute: String? {
        root.swiftModel.telemetry.configuration.actionNameAttribute
    }

    @objc public var allowFallbackToLocalStorage: NSNumber? {
        root.swiftModel.telemetry.configuration.allowFallbackToLocalStorage as NSNumber?
    }

    @objc public var allowUntrustedEvents: NSNumber? {
        root.swiftModel.telemetry.configuration.allowUntrustedEvents as NSNumber?
    }

    @objc public var appHangThreshold: NSNumber? {
        root.swiftModel.telemetry.configuration.appHangThreshold as NSNumber?
    }

    @objc public var backgroundTasksEnabled: NSNumber? {
        root.swiftModel.telemetry.configuration.backgroundTasksEnabled as NSNumber?
    }

    @objc public var batchProcessingLevel: NSNumber? {
        root.swiftModel.telemetry.configuration.batchProcessingLevel as NSNumber?
    }

    @objc public var batchSize: NSNumber? {
        root.swiftModel.telemetry.configuration.batchSize as NSNumber?
    }

    @objc public var batchUploadFrequency: NSNumber? {
        root.swiftModel.telemetry.configuration.batchUploadFrequency as NSNumber?
    }

    @objc public var compressIntakeRequests: NSNumber? {
        root.swiftModel.telemetry.configuration.compressIntakeRequests as NSNumber?
    }

    @objc public var dartVersion: String? {
        set { root.swiftModel.telemetry.configuration.dartVersion = newValue }
        get { root.swiftModel.telemetry.configuration.dartVersion }
    }

    @objc public var defaultPrivacyLevel: String? {
        set { root.swiftModel.telemetry.configuration.defaultPrivacyLevel = newValue }
        get { root.swiftModel.telemetry.configuration.defaultPrivacyLevel }
    }

    @objc public var enablePrivacyForActionName: NSNumber? {
        set { root.swiftModel.telemetry.configuration.enablePrivacyForActionName = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.enablePrivacyForActionName as NSNumber? }
    }

    @objc public var forwardConsoleLogs: DDTelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs? {
        root.swiftModel.telemetry.configuration.forwardConsoleLogs != nil ? DDTelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs(root: root) : nil
    }

    @objc public var forwardErrorsToLogs: NSNumber? {
        root.swiftModel.telemetry.configuration.forwardErrorsToLogs as NSNumber?
    }

    @objc public var forwardReports: DDTelemetryConfigurationEventTelemetryConfigurationForwardReports? {
        root.swiftModel.telemetry.configuration.forwardReports != nil ? DDTelemetryConfigurationEventTelemetryConfigurationForwardReports(root: root) : nil
    }

    @objc public var initializationType: String? {
        set { root.swiftModel.telemetry.configuration.initializationType = newValue }
        get { root.swiftModel.telemetry.configuration.initializationType }
    }

    @objc public var mobileVitalsUpdatePeriod: NSNumber? {
        set { root.swiftModel.telemetry.configuration.mobileVitalsUpdatePeriod = newValue?.int64Value }
        get { root.swiftModel.telemetry.configuration.mobileVitalsUpdatePeriod as NSNumber? }
    }

    @objc public var premiumSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.premiumSampleRate as NSNumber?
    }

    @objc public var reactNativeVersion: String? {
        set { root.swiftModel.telemetry.configuration.reactNativeVersion = newValue }
        get { root.swiftModel.telemetry.configuration.reactNativeVersion }
    }

    @objc public var reactVersion: String? {
        set { root.swiftModel.telemetry.configuration.reactVersion = newValue }
        get { root.swiftModel.telemetry.configuration.reactVersion }
    }

    @objc public var replaySampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.replaySampleRate as NSNumber?
    }

    @objc public var selectedTracingPropagators: [Int]? {
        root.swiftModel.telemetry.configuration.selectedTracingPropagators?.map { DDTelemetryConfigurationEventTelemetryConfigurationSelectedTracingPropagators(swift: $0).rawValue }
    }

    @objc public var sendLogsAfterSessionExpiration: NSNumber? {
        set { root.swiftModel.telemetry.configuration.sendLogsAfterSessionExpiration = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.sendLogsAfterSessionExpiration as NSNumber? }
    }

    @objc public var sessionReplaySampleRate: NSNumber? {
        set { root.swiftModel.telemetry.configuration.sessionReplaySampleRate = newValue?.int64Value }
        get { root.swiftModel.telemetry.configuration.sessionReplaySampleRate as NSNumber? }
    }

    @objc public var sessionSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.sessionSampleRate as NSNumber?
    }

    @objc public var silentMultipleInit: NSNumber? {
        root.swiftModel.telemetry.configuration.silentMultipleInit as NSNumber?
    }

    @objc public var startSessionReplayRecordingManually: NSNumber? {
        set { root.swiftModel.telemetry.configuration.startSessionReplayRecordingManually = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.startSessionReplayRecordingManually as NSNumber? }
    }

    @objc public var storeContextsAcrossPages: NSNumber? {
        root.swiftModel.telemetry.configuration.storeContextsAcrossPages as NSNumber?
    }

    @objc public var telemetryConfigurationSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.telemetryConfigurationSampleRate as NSNumber?
    }

    @objc public var telemetrySampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.telemetrySampleRate as NSNumber?
    }

    @objc public var telemetryUsageSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.telemetryUsageSampleRate as NSNumber?
    }

    @objc public var traceContextInjection: DDTelemetryConfigurationEventTelemetryConfigurationTraceContextInjection {
        set { root.swiftModel.telemetry.configuration.traceContextInjection = newValue.toSwift }
        get { .init(swift: root.swiftModel.telemetry.configuration.traceContextInjection) }
    }

    @objc public var traceSampleRate: NSNumber? {
        root.swiftModel.telemetry.configuration.traceSampleRate as NSNumber?
    }

    @objc public var tracerApi: String? {
        set { root.swiftModel.telemetry.configuration.tracerApi = newValue }
        get { root.swiftModel.telemetry.configuration.tracerApi }
    }

    @objc public var tracerApiVersion: String? {
        set { root.swiftModel.telemetry.configuration.tracerApiVersion = newValue }
        get { root.swiftModel.telemetry.configuration.tracerApiVersion }
    }

    @objc public var trackBackgroundEvents: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackBackgroundEvents = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackBackgroundEvents as NSNumber? }
    }

    @objc public var trackCrossPlatformLongTasks: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackCrossPlatformLongTasks = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackCrossPlatformLongTasks as NSNumber? }
    }

    @objc public var trackErrors: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackErrors = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackErrors as NSNumber? }
    }

    @objc public var trackFlutterPerformance: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackFlutterPerformance = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackFlutterPerformance as NSNumber? }
    }

    @objc public var trackFrustrations: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackFrustrations = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackFrustrations as NSNumber? }
    }

    @objc public var trackInteractions: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackInteractions = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackInteractions as NSNumber? }
    }

    @objc public var trackLongTask: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackLongTask = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackLongTask as NSNumber? }
    }

    @objc public var trackNativeErrors: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNativeErrors = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNativeErrors as NSNumber? }
    }

    @objc public var trackNativeLongTasks: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNativeLongTasks = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNativeLongTasks as NSNumber? }
    }

    @objc public var trackNativeViews: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNativeViews = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNativeViews as NSNumber? }
    }

    @objc public var trackNetworkRequests: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackNetworkRequests = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackNetworkRequests as NSNumber? }
    }

    @objc public var trackResources: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackResources = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackResources as NSNumber? }
    }

    @objc public var trackSessionAcrossSubdomains: NSNumber? {
        root.swiftModel.telemetry.configuration.trackSessionAcrossSubdomains as NSNumber?
    }

    @objc public var trackUserInteractions: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackUserInteractions = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackUserInteractions as NSNumber? }
    }

    @objc public var trackViewsManually: NSNumber? {
        set { root.swiftModel.telemetry.configuration.trackViewsManually = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.trackViewsManually as NSNumber? }
    }

    @objc public var trackingConsent: DDTelemetryConfigurationEventTelemetryConfigurationTrackingConsent {
        .init(swift: root.swiftModel.telemetry.configuration.trackingConsent)
    }

    @objc public var unityVersion: String? {
        set { root.swiftModel.telemetry.configuration.unityVersion = newValue }
        get { root.swiftModel.telemetry.configuration.unityVersion }
    }

    @objc public var useAllowedTracingOrigins: NSNumber? {
        root.swiftModel.telemetry.configuration.useAllowedTracingOrigins as NSNumber?
    }

    @objc public var useAllowedTracingUrls: NSNumber? {
        root.swiftModel.telemetry.configuration.useAllowedTracingUrls as NSNumber?
    }

    @objc public var useBeforeSend: NSNumber? {
        root.swiftModel.telemetry.configuration.useBeforeSend as NSNumber?
    }

    @objc public var useCrossSiteSessionCookie: NSNumber? {
        root.swiftModel.telemetry.configuration.useCrossSiteSessionCookie as NSNumber?
    }

    @objc public var useExcludedActivityUrls: NSNumber? {
        root.swiftModel.telemetry.configuration.useExcludedActivityUrls as NSNumber?
    }

    @objc public var useFirstPartyHosts: NSNumber? {
        set { root.swiftModel.telemetry.configuration.useFirstPartyHosts = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.useFirstPartyHosts as NSNumber? }
    }

    @objc public var useLocalEncryption: NSNumber? {
        root.swiftModel.telemetry.configuration.useLocalEncryption as NSNumber?
    }

    @objc public var usePartitionedCrossSiteSessionCookie: NSNumber? {
        root.swiftModel.telemetry.configuration.usePartitionedCrossSiteSessionCookie as NSNumber?
    }

    @objc public var usePciIntake: NSNumber? {
        set { root.swiftModel.telemetry.configuration.usePciIntake = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.usePciIntake as NSNumber? }
    }

    @objc public var useProxy: NSNumber? {
        set { root.swiftModel.telemetry.configuration.useProxy = newValue?.boolValue }
        get { root.swiftModel.telemetry.configuration.useProxy as NSNumber? }
    }

    @objc public var useSecureSessionCookie: NSNumber? {
        root.swiftModel.telemetry.configuration.useSecureSessionCookie as NSNumber?
    }

    @objc public var useTracing: NSNumber? {
        root.swiftModel.telemetry.configuration.useTracing as NSNumber?
    }

    @objc public var useWorkerUrl: NSNumber? {
        root.swiftModel.telemetry.configuration.useWorkerUrl as NSNumber?
    }

    @objc public var viewTrackingStrategy: DDTelemetryConfigurationEventTelemetryConfigurationViewTrackingStrategy {
        .init(swift: root.swiftModel.telemetry.configuration.viewTrackingStrategy)
    }
}

@objc
public class DDTelemetryConfigurationEventTelemetryConfigurationForwardConsoleLogs: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.telemetry.configuration.forwardConsoleLogs else {
            return nil
        }
        return value
    }

    @objc public var string: String? {
        guard case .string(let value) = root.swiftModel.telemetry.configuration.forwardConsoleLogs else {
            return nil
        }
        return value
    }
}

@objc
public class DDTelemetryConfigurationEventTelemetryConfigurationForwardReports: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var stringsArray: [String]? {
        guard case .stringsArray(let value) = root.swiftModel.telemetry.configuration.forwardReports else {
            return nil
        }
        return value
    }

    @objc public var string: String? {
        guard case .string(let value) = root.swiftModel.telemetry.configuration.forwardReports else {
            return nil
        }
        return value
    }
}

@objc
public enum DDTelemetryConfigurationEventTelemetryConfigurationSelectedTracingPropagators: Int {
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

@objc
public enum DDTelemetryConfigurationEventTelemetryConfigurationTraceContextInjection: Int {
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

@objc
public enum DDTelemetryConfigurationEventTelemetryConfigurationTrackingConsent: Int {
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

@objc
public enum DDTelemetryConfigurationEventTelemetryConfigurationViewTrackingStrategy: Int {
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

@objc
public class DDTelemetryConfigurationEventTelemetryRUMTelemetryDevice: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var architecture: String? {
        root.swiftModel.telemetry.device!.architecture
    }

    @objc public var brand: String? {
        root.swiftModel.telemetry.device!.brand
    }

    @objc public var model: String? {
        root.swiftModel.telemetry.device!.model
    }
}

@objc
public class DDTelemetryConfigurationEventTelemetryRUMTelemetryOperatingSystem: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var build: String? {
        root.swiftModel.telemetry.os!.build
    }

    @objc public var name: String? {
        root.swiftModel.telemetry.os!.name
    }

    @objc public var version: String? {
        root.swiftModel.telemetry.os!.version
    }
}

@objc
public class DDTelemetryConfigurationEventView: NSObject {
    internal let root: DDTelemetryConfigurationEvent

    internal init(root: DDTelemetryConfigurationEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.view!.id
    }
}

// swiftlint:enable force_unwrapping

// Generated from https://github.com/DataDog/rum-events-format/tree/30d4b773abb4e33edc9d6053d3c12cd302e948a5
