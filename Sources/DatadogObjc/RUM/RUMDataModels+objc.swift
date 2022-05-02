/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog
import Foundation

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

    @objc public var ciTest: DDRUMActionEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMActionEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMActionEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMActionEventRUMConnectivity(root: root) : nil
    }

    @objc public var context: DDRUMActionEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMActionEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
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

    @objc public var synthetics: DDRUMActionEventSynthetics? {
        root.swiftModel.synthetics != nil ? DDRUMActionEventSynthetics(root: root) : nil
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

    @objc public var browserSdkVersion: String? {
        root.swiftModel.dd.browserSdkVersion
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMActionEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMActionEventDDSession(root: root) : nil
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
}

@objc
public enum DDRUMActionEventDDSessionPlan: Int {
    internal init(swift: RUMActionEvent.DD.Session.Plan) {
        switch swift {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }

    internal var toSwift: RUMActionEvent.DD.Session.Plan {
        switch self {
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case plan1
    case plan2
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

    @objc public var frustrationType: [Int]? {
        root.swiftModel.action.frustrationType?.map { DDRUMActionEventActionFrustrationType(swift: $0).rawValue }
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
public enum DDRUMActionEventActionFrustrationType: Int {
    internal init(swift: RUMActionEvent.Action.FrustrationType?) {
        switch swift {
        case nil: self = .none
        case .rage?: self = .rage
        case .dead?: self = .dead
        case .error?: self = .error
        }
    }

    internal var toSwift: RUMActionEvent.Action.FrustrationType? {
        switch self {
        case .none: return nil
        case .rage: return .rage
        case .dead: return .dead
        case .error: return .error
        }
    }

    case none
    case rage
    case dead
    case error
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

    @objc public var interfaces: [Int] {
        root.swiftModel.connectivity!.interfaces.map { DDRUMActionEventRUMConnectivityInterfaces(swift: $0).rawValue }
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
public enum DDRUMActionEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces) {
        switch swift {
        case .bluetooth: self = .bluetooth
        case .cellular: self = .cellular
        case .ethernet: self = .ethernet
        case .wifi: self = .wifi
        case .wimax: self = .wimax
        case .mixed: self = .mixed
        case .other: self = .other
        case .unknown: self = .unknown
        case .none: self = .none
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces {
        switch self {
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .none: return .none
        }
    }

    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case none
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

    @objc public var type: DDRUMActionEventSessionSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMActionEventSessionSessionType: Int {
    internal init(swift: RUMActionEvent.Session.SessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMActionEvent.Session.SessionType {
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
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDRUMActionEventSynthetics: NSObject {
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

    @objc public var ciTest: DDRUMErrorEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMErrorEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMErrorEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMErrorEventRUMConnectivity(root: root) : nil
    }

    @objc public var context: DDRUMErrorEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMErrorEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var error: DDRUMErrorEventError {
        DDRUMErrorEventError(root: root)
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

    @objc public var synthetics: DDRUMErrorEventSynthetics? {
        root.swiftModel.synthetics != nil ? DDRUMErrorEventSynthetics(root: root) : nil
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

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMErrorEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMErrorEventDDSession(root: root) : nil
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
}

@objc
public enum DDRUMErrorEventDDSessionPlan: Int {
    internal init(swift: RUMErrorEvent.DD.Session.Plan) {
        switch swift {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }

    internal var toSwift: RUMErrorEvent.DD.Session.Plan {
        switch self {
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case plan1
    case plan2
}

@objc
public class DDRUMErrorEventAction: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.action!.id
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

    @objc public var interfaces: [Int] {
        root.swiftModel.connectivity!.interfaces.map { DDRUMErrorEventRUMConnectivityInterfaces(swift: $0).rawValue }
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
public enum DDRUMErrorEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces) {
        switch swift {
        case .bluetooth: self = .bluetooth
        case .cellular: self = .cellular
        case .ethernet: self = .ethernet
        case .wifi: self = .wifi
        case .wimax: self = .wimax
        case .mixed: self = .mixed
        case .other: self = .other
        case .unknown: self = .unknown
        case .none: self = .none
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces {
        switch self {
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .none: return .none
        }
    }

    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case none
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
public class DDRUMErrorEventError: NSObject {
    internal let root: DDRUMErrorEvent

    internal init(root: DDRUMErrorEvent) {
        self.root = root
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

    @objc public var type: String? {
        root.swiftModel.error.type
    }
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
        }
    }

    case post
    case get
    case head
    case put
    case delete
    case patch
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
        }
    }

    case none
    case android
    case browser
    case ios
    case reactNative
    case flutter
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

    @objc public var type: DDRUMErrorEventSessionSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMErrorEventSessionSessionType: Int {
    internal init(swift: RUMErrorEvent.Session.SessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMErrorEvent.Session.SessionType {
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
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDRUMErrorEventSynthetics: NSObject {
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

    @objc public var ciTest: DDRUMLongTaskEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMLongTaskEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMLongTaskEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMLongTaskEventRUMConnectivity(root: root) : nil
    }

    @objc public var context: DDRUMLongTaskEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMLongTaskEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
    }

    @objc public var longTask: DDRUMLongTaskEventLongTask {
        DDRUMLongTaskEventLongTask(root: root)
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

    @objc public var synthetics: DDRUMLongTaskEventSynthetics? {
        root.swiftModel.synthetics != nil ? DDRUMLongTaskEventSynthetics(root: root) : nil
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

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMLongTaskEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMLongTaskEventDDSession(root: root) : nil
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
}

@objc
public enum DDRUMLongTaskEventDDSessionPlan: Int {
    internal init(swift: RUMLongTaskEvent.DD.Session.Plan) {
        switch swift {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }

    internal var toSwift: RUMLongTaskEvent.DD.Session.Plan {
        switch self {
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case plan1
    case plan2
}

@objc
public class DDRUMLongTaskEventAction: NSObject {
    internal let root: DDRUMLongTaskEvent

    internal init(root: DDRUMLongTaskEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.action!.id
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

    @objc public var interfaces: [Int] {
        root.swiftModel.connectivity!.interfaces.map { DDRUMLongTaskEventRUMConnectivityInterfaces(swift: $0).rawValue }
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
public enum DDRUMLongTaskEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces) {
        switch swift {
        case .bluetooth: self = .bluetooth
        case .cellular: self = .cellular
        case .ethernet: self = .ethernet
        case .wifi: self = .wifi
        case .wimax: self = .wimax
        case .mixed: self = .mixed
        case .other: self = .other
        case .unknown: self = .unknown
        case .none: self = .none
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces {
        switch self {
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .none: return .none
        }
    }

    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case none
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

    @objc public var type: DDRUMLongTaskEventSessionSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMLongTaskEventSessionSessionType: Int {
    internal init(swift: RUMLongTaskEvent.Session.SessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMLongTaskEvent.Session.SessionType {
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
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDRUMLongTaskEventSynthetics: NSObject {
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

    @objc public var ciTest: DDRUMResourceEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMResourceEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMResourceEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMResourceEventRUMConnectivity(root: root) : nil
    }

    @objc public var context: DDRUMResourceEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMResourceEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
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

    @objc public var synthetics: DDRUMResourceEventSynthetics? {
        root.swiftModel.synthetics != nil ? DDRUMResourceEventSynthetics(root: root) : nil
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

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
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
public class DDRUMResourceEventDDSession: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var plan: DDRUMResourceEventDDSessionPlan {
        .init(swift: root.swiftModel.dd.session!.plan)
    }
}

@objc
public enum DDRUMResourceEventDDSessionPlan: Int {
    internal init(swift: RUMResourceEvent.DD.Session.Plan) {
        switch swift {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }

    internal var toSwift: RUMResourceEvent.DD.Session.Plan {
        switch self {
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case plan1
    case plan2
}

@objc
public class DDRUMResourceEventAction: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var id: String {
        root.swiftModel.action!.id
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

    @objc public var interfaces: [Int] {
        root.swiftModel.connectivity!.interfaces.map { DDRUMResourceEventRUMConnectivityInterfaces(swift: $0).rawValue }
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
public enum DDRUMResourceEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces) {
        switch swift {
        case .bluetooth: self = .bluetooth
        case .cellular: self = .cellular
        case .ethernet: self = .ethernet
        case .wifi: self = .wifi
        case .wimax: self = .wimax
        case .mixed: self = .mixed
        case .other: self = .other
        case .unknown: self = .unknown
        case .none: self = .none
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces {
        switch self {
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .none: return .none
        }
    }

    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case none
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
public class DDRUMResourceEventResource: NSObject {
    internal let root: DDRUMResourceEvent

    internal init(root: DDRUMResourceEvent) {
        self.root = root
    }

    @objc public var connect: DDRUMResourceEventResourceConnect? {
        root.swiftModel.resource.connect != nil ? DDRUMResourceEventResourceConnect(root: root) : nil
    }

    @objc public var dns: DDRUMResourceEventResourceDNS? {
        root.swiftModel.resource.dns != nil ? DDRUMResourceEventResourceDNS(root: root) : nil
    }

    @objc public var download: DDRUMResourceEventResourceDownload? {
        root.swiftModel.resource.download != nil ? DDRUMResourceEventResourceDownload(root: root) : nil
    }

    @objc public var duration: NSNumber {
        root.swiftModel.resource.duration as NSNumber
    }

    @objc public var firstByte: DDRUMResourceEventResourceFirstByte? {
        root.swiftModel.resource.firstByte != nil ? DDRUMResourceEventResourceFirstByte(root: root) : nil
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

    @objc public var size: NSNumber? {
        root.swiftModel.resource.size as NSNumber?
    }

    @objc public var ssl: DDRUMResourceEventResourceSSL? {
        root.swiftModel.resource.ssl != nil ? DDRUMResourceEventResourceSSL(root: root) : nil
    }

    @objc public var statusCode: NSNumber? {
        root.swiftModel.resource.statusCode as NSNumber?
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
        }
    }

    case none
    case post
    case get
    case head
    case put
    case delete
    case patch
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

    @objc public var type: DDRUMResourceEventSessionSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMResourceEventSessionSessionType: Int {
    internal init(swift: RUMResourceEvent.Session.SessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMResourceEvent.Session.SessionType {
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
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDRUMResourceEventSynthetics: NSObject {
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

    @objc public var ciTest: DDRUMViewEventRUMCITest? {
        root.swiftModel.ciTest != nil ? DDRUMViewEventRUMCITest(root: root) : nil
    }

    @objc public var connectivity: DDRUMViewEventRUMConnectivity? {
        root.swiftModel.connectivity != nil ? DDRUMViewEventRUMConnectivity(root: root) : nil
    }

    @objc public var context: DDRUMViewEventRUMEventAttributes? {
        root.swiftModel.context != nil ? DDRUMViewEventRUMEventAttributes(root: root) : nil
    }

    @objc public var date: NSNumber {
        root.swiftModel.date as NSNumber
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

    @objc public var synthetics: DDRUMViewEventSynthetics? {
        root.swiftModel.synthetics != nil ? DDRUMViewEventSynthetics(root: root) : nil
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

    @objc public var documentVersion: NSNumber {
        root.swiftModel.dd.documentVersion as NSNumber
    }

    @objc public var formatVersion: NSNumber {
        root.swiftModel.dd.formatVersion as NSNumber
    }

    @objc public var session: DDRUMViewEventDDSession? {
        root.swiftModel.dd.session != nil ? DDRUMViewEventDDSession(root: root) : nil
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
}

@objc
public enum DDRUMViewEventDDSessionPlan: Int {
    internal init(swift: RUMViewEvent.DD.Session.Plan) {
        switch swift {
        case .plan1: self = .plan1
        case .plan2: self = .plan2
        }
    }

    internal var toSwift: RUMViewEvent.DD.Session.Plan {
        switch self {
        case .plan1: return .plan1
        case .plan2: return .plan2
        }
    }

    case plan1
    case plan2
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

    @objc public var interfaces: [Int] {
        root.swiftModel.connectivity!.interfaces.map { DDRUMViewEventRUMConnectivityInterfaces(swift: $0).rawValue }
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
public enum DDRUMViewEventRUMConnectivityInterfaces: Int {
    internal init(swift: RUMConnectivity.Interfaces) {
        switch swift {
        case .bluetooth: self = .bluetooth
        case .cellular: self = .cellular
        case .ethernet: self = .ethernet
        case .wifi: self = .wifi
        case .wimax: self = .wimax
        case .mixed: self = .mixed
        case .other: self = .other
        case .unknown: self = .unknown
        case .none: self = .none
        }
    }

    internal var toSwift: RUMConnectivity.Interfaces {
        switch self {
        case .bluetooth: return .bluetooth
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        case .wifi: return .wifi
        case .wimax: return .wimax
        case .mixed: return .mixed
        case .other: return .other
        case .unknown: return .unknown
        case .none: return .none
        }
    }

    case bluetooth
    case cellular
    case ethernet
    case wifi
    case wimax
    case mixed
    case other
    case unknown
    case none
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

    @objc public var type: DDRUMViewEventSessionSessionType {
        .init(swift: root.swiftModel.session.type)
    }
}

@objc
public enum DDRUMViewEventSessionSessionType: Int {
    internal init(swift: RUMViewEvent.Session.SessionType) {
        switch swift {
        case .user: self = .user
        case .synthetics: self = .synthetics
        case .ciTest: self = .ciTest
        }
    }

    internal var toSwift: RUMViewEvent.Session.SessionType {
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
        }
    }

    case none
    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDRUMViewEventSynthetics: NSObject {
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

    @objc public var firstContentfulPaint: NSNumber? {
        root.swiftModel.view.firstContentfulPaint as NSNumber?
    }

    @objc public var firstInputDelay: NSNumber? {
        root.swiftModel.view.firstInputDelay as NSNumber?
    }

    @objc public var firstInputTime: NSNumber? {
        root.swiftModel.view.firstInputTime as NSNumber?
    }

    @objc public var frozenFrame: DDRUMViewEventViewFrozenFrame? {
        root.swiftModel.view.frozenFrame != nil ? DDRUMViewEventViewFrozenFrame(root: root) : nil
    }

    @objc public var id: String {
        root.swiftModel.view.id
    }

    @objc public var inForegroundPeriods: [DDRUMViewEventViewInForegroundPeriods]? {
        root.swiftModel.view.inForegroundPeriods?.map { DDRUMViewEventViewInForegroundPeriods(swiftModel: $0) }
    }

    @objc public var isActive: NSNumber? {
        root.swiftModel.view.isActive as NSNumber?
    }

    @objc public var isSlowRendered: NSNumber? {
        root.swiftModel.view.isSlowRendered as NSNumber?
    }

    @objc public var largestContentfulPaint: NSNumber? {
        root.swiftModel.view.largestContentfulPaint as NSNumber?
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
public class DDRUMViewEventViewInForegroundPeriods: NSObject {
    internal let swiftModel: RUMViewEvent.View.InForegroundPeriods
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
        }
    }

    internal var toSwift: TelemetryErrorEvent.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDTelemetryErrorEventTelemetry: NSObject {
    internal let root: DDTelemetryErrorEvent

    internal init(root: DDTelemetryErrorEvent) {
        self.root = root
    }

    @objc public var error: DDTelemetryErrorEventTelemetryError? {
        root.swiftModel.telemetry.error != nil ? DDTelemetryErrorEventTelemetryError(root: root) : nil
    }

    @objc public var message: String {
        root.swiftModel.telemetry.message
    }

    @objc public var status: String {
        root.swiftModel.telemetry.status
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
        }
    }

    internal var toSwift: TelemetryDebugEvent.Source {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .browser: return .browser
        case .flutter: return .flutter
        case .reactNative: return .reactNative
        }
    }

    case android
    case ios
    case browser
    case flutter
    case reactNative
}

@objc
public class DDTelemetryDebugEventTelemetry: NSObject {
    internal let root: DDTelemetryDebugEvent

    internal init(root: DDTelemetryDebugEvent) {
        self.root = root
    }

    @objc public var message: String {
        root.swiftModel.telemetry.message
    }

    @objc public var status: String {
        root.swiftModel.telemetry.status
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

// swiftlint:enable force_unwrapping

// Generated from https://github.com/DataDog/rum-events-format/tree/568fc1bcfb0d2775a11c07914120b70a3d5780fe
