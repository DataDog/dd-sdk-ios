/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
@_spi(objc)
import DatadogInternal

internal struct UIKitRUMViewsPredicateBridge: UIKitRUMViewsPredicate {
    let objcPredicate: objc_UIKitRUMViewsPredicate

    func rumView(for viewController: UIViewController) -> RUMView? {
        return objcPredicate.rumView(for: viewController)?.swiftView
    }
}

@objc(DDRUMView)
@objcMembers
@_spi(objc)
public class objc_RUMView: NSObject {
    let swiftView: RUMView

    public var name: String { swiftView.name }
    public var attributes: [String: Any] { swiftView.attributes.dd.objCAttributes }

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - name: the RUM View name, appearing as `VIEW NAME` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    public init(name: String, attributes: [String: Any]) {
        swiftView = RUMView(
            name: name,
            attributes: attributes.dd.swiftAttributes
        )
    }
}

@objc(DDUIKitRUMViewsPredicate)
@_spi(objc)
public protocol objc_UIKitRUMViewsPredicate: AnyObject {
    /// The predicate deciding if the RUM View should be started or ended for given instance of the `UIViewController`.
    /// - Parameter viewController: an instance of the view controller noticed by the SDK.
    /// - Returns: RUM View parameters if received view controller should start/end the RUM View, `nil` otherwise.
    func rumView(for viewController: UIViewController) -> objc_RUMView?
}

@objc(DDDefaultUIKitRUMViewsPredicate)
@objcMembers
@_spi(objc)
public class objc_DefaultUIKitRUMViewsPredicate: NSObject, objc_UIKitRUMViewsPredicate {
    private let swiftPredicate = DefaultUIKitRUMViewsPredicate()

    public func rumView(for viewController: UIViewController) -> objc_RUMView? {
        return swiftPredicate.rumView(for: viewController).map {
            objc_RUMView(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
}

@objc(DDDefaultUIKitRUMActionsPredicate)
@objcMembers
@_spi(objc)
public class objc_DefaultUIKitRUMActionsPredicate: NSObject, objc_UIKitRUMActionsPredicate {
    let swiftPredicate = DefaultUIKitRUMActionsPredicate()
    #if os(tvOS)
    public func rumAction(press type: UIPress.PressType, targetView: UIView) -> objc_RUMAction? {
        swiftPredicate.rumAction(press: type, targetView: targetView).map {
            objc_RUMAction(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
    #else
    public func rumAction(targetView: UIView) -> objc_RUMAction? {
        swiftPredicate.rumAction(targetView: targetView).map {
            objc_RUMAction(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
    #endif
}

internal struct UIKitRUMActionsPredicateBridge: UITouchRUMActionsPredicate & UIPressRUMActionsPredicate {
    let objcPredicate: AnyObject?

    init(objcPredicate: objc_UITouchRUMActionsPredicate) {
        self.objcPredicate = objcPredicate
    }

    init(objcPredicate: objc_UIPressRUMActionsPredicate) {
        self.objcPredicate = objcPredicate
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        guard let objcPredicate = objcPredicate as? objc_UITouchRUMActionsPredicate else {
            return nil
        }
        return objcPredicate.rumAction(targetView: targetView)?.swiftAction
    }

    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        guard let objcPredicate = objcPredicate as? objc_UIPressRUMActionsPredicate else {
            return nil
        }
        return objcPredicate.rumAction(press: type, targetView: targetView)?.swiftAction
    }
}

@objc(DDRUMAction)
@objcMembers
@_spi(objc)
public class objc_RUMAction: NSObject {
    let swiftAction: RUMAction

    public var name: String { swiftAction.name }
    public var attributes: [String: Any] { swiftAction.attributes.dd.objCAttributes }

    /// Initializes the RUM Action description.
    /// - Parameters:
    ///   - name: the RUM Action name, appearing as `ACTION NAME` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM Action.
    public init(name: String, attributes: [String: Any]) {
        swiftAction = RUMAction(
            name: name,
            attributes: attributes.dd.swiftAttributes
        )
    }
}

#if os(tvOS)
@objc(DDUIKitRUMActionsPredicate)
@_spi(objc)
public protocol objc_UIKitRUMActionsPredicate: objc_UIPressRUMActionsPredicate {}
#else
@objc(DDUIKitRUMActionsPredicate)
@_spi(objc)
public protocol objc_UIKitRUMActionsPredicate: objc_UITouchRUMActionsPredicate {}
#endif

@objc(DDUITouchRUMActionsPredicate)
@_spi(objc)
public protocol objc_UITouchRUMActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: UIView) -> objc_RUMAction?
}

@objc(DDUIPressRUMActionsPredicate)
@_spi(objc)
public protocol objc_UIPressRUMActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameters:
    ///   - type: the `UIPress.PressType` which received the action.
    ///   - targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(press type: UIPress.PressType, targetView: UIView) -> objc_RUMAction?
}

@objc(DDRUMErrorSource)
@_spi(objc)
public enum objc_RUMErrorSource: Int {
    /// Error originated in the source code.
    case source
    /// Error originated in the network layer.
    case network
    /// Error originated in a webview.
    case webview
    /// Error originated in a web console (used by bridges).
    case console
    /// Custom error source.
    case custom

    internal var swiftType: RUMErrorSource {
        switch self {
        case .source: return .source
        case .network: return .network
        case .webview: return .webview
        case .custom: return .custom
        case .console: return .console
        default: return .custom
        }
    }
}

@objc(DDRUMActionType)
@_spi(objc)
public enum objc_RUMActionType: Int {
    case tap
    case scroll
    case swipe
    case custom

    internal var swiftType: RUMActionType {
        switch self {
        case .tap: return .tap
        case .scroll: return .scroll
        case .swipe: return .swipe
        case .custom: return .custom
        default: return .custom
        }
    }
}

@objc(DDRUMResourceType)
@_spi(objc)
public enum objc_ResourceType: Int {
    case image
    case xhr
    case beacon
    case css
    case document
    case fetch
    case font
    case js
    case media
    case other
    case native

    internal var swiftType: RUMResourceType {
        switch self {
        case .image: return .image
        case .xhr: return .xhr
        case .beacon: return .beacon
        case .css: return .css
        case .document: return .document
        case .fetch: return .fetch
        case .font: return .font
        case .js: return .js
        case .media: return .media
        case .native: return .native
        default: return .other
        }
    }
}

@objc(DDRUMMethod)
@_spi(objc)
public enum objc_RUMMethod: Int {
    case post
    case get
    case head
    case put
    case delete
    case patch
    case connect
    case trace
    case options

    internal var swiftType: RUMMethod {
        switch self {
        case .post: return .post
        case .get: return .get
        case .head: return .head
        case .put: return .put
        case .delete: return .delete
        case .patch: return .patch
        case .connect: return .connect
        case .trace: return .trace
        case .options: return .options
        default: return .get
        }
    }
}

@objc(DDRUMVitalsFrequency)
@_spi(objc)
public enum objc_VitalsFrequency: Int {
    case frequent
    case average
    case rare
    case never

    internal init(swiftType: DatadogRUM.RUM.Configuration.VitalsFrequency?) {
        switch swiftType {
        case .frequent: self = .frequent
        case .average: self = .average
        case .rare: self = .rare
        case .none: self = .never
        }
    }

    internal var swiftType: DatadogRUM.RUM.Configuration.VitalsFrequency? {
        switch self {
        case .frequent: return .frequent
        case .average: return .average
        case .rare: return .rare
        case .never: return nil
        }
    }
}

@objc(DDRUMFirstPartyHostsTracing)
@objcMembers
@_spi(objc)
public class objc_FirstPartyHostsTracing: NSObject {
    internal var swiftType: RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing

    public init(hostsWithHeaderTypes: [String: Set<objc_TracingHeaderType>]) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in Set(headerTypes.map { $0.swiftType }) }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders)
    }

    public init(hostsWithHeaderTypes: [String: Set<objc_TracingHeaderType>], sampleRate: Float) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in Set(headerTypes.map { $0.swiftType }) }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders, sampleRate: sampleRate)
    }

    public init(hosts: Set<String>) {
        swiftType = .trace(hosts: hosts)
    }

    public init(hosts: Set<String>, sampleRate: Float) {
        swiftType = .trace(hosts: hosts, sampleRate: sampleRate)
    }
}

@objc(DDRUMURLSessionTracking)
@objcMembers
@_spi(objc)
public class objc_URLSessionTracking: NSObject {
    internal var swiftConfig: RUM.Configuration.URLSessionTracking

    override public init() {
        swiftConfig = .init()
    }

    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: objc_FirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }

    public func setResourceAttributesProvider(_ provider: @escaping (URLRequest, URLResponse?, Data?, Error?) -> [String: Any]?) {
        swiftConfig.resourceAttributesProvider = { request, response, data, error in
            let objcAttributes = provider(request, response, data, error)
            return objcAttributes?.dd.swiftAttributes
        }
    }
}

@objc(DDRUMConfiguration)
@objcMembers
@_spi(objc)
public class objc_RUMConfiguration: NSObject {
    internal var swiftConfig: DatadogRUM.RUM.Configuration

    public init(applicationID: String) {
        swiftConfig = .init(applicationID: applicationID)
    }

    public var applicationID: String {
        swiftConfig.applicationID
    }

    public var sessionSampleRate: Float {
        set { swiftConfig.sessionSampleRate = newValue }
        get { swiftConfig.sessionSampleRate }
    }

    public var telemetrySampleRate: Float {
        set { swiftConfig.telemetrySampleRate = newValue }
        get { swiftConfig.telemetrySampleRate }
    }

    public var uiKitViewsPredicate: objc_UIKitRUMViewsPredicate? {
        set { swiftConfig.uiKitViewsPredicate = newValue.map { UIKitRUMViewsPredicateBridge(objcPredicate: $0) } }
        get { (swiftConfig.uiKitViewsPredicate as? UIKitRUMViewsPredicateBridge)?.objcPredicate  }
    }

    public var uiKitActionsPredicate: objc_UIKitRUMActionsPredicate? {
        set { swiftConfig.uiKitActionsPredicate = newValue.map { UIKitRUMActionsPredicateBridge(objcPredicate: $0) } }
        get { (swiftConfig.uiKitActionsPredicate as? UIKitRUMActionsPredicateBridge)?.objcPredicate as? objc_UIKitRUMActionsPredicate  }
    }

    public var swiftUIViewsPredicate: objc_SwiftUIRUMViewsPredicate? {
        set { swiftConfig.swiftUIViewsPredicate = newValue.map { SwiftUIRUMViewsPredicateBridge(objcPredicate: $0) } }
        get { (swiftConfig.swiftUIViewsPredicate as? SwiftUIRUMViewsPredicateBridge)?.objcPredicate }
    }

    public var swiftUIActionsPredicate: objc_SwiftUIRUMActionsPredicate? {
        set { swiftConfig.swiftUIActionsPredicate = newValue.map { SwiftUIRUMActionsPredicateBridge(objcPredicate: $0) } }
        get { (swiftConfig.swiftUIActionsPredicate as? SwiftUIRUMActionsPredicateBridge)?.objcPredicate }
    }

    public func setURLSessionTracking(_ tracking: objc_URLSessionTracking) {
        swiftConfig.urlSessionTracking = tracking.swiftConfig
    }

    public var trackFrustrations: Bool {
        set { swiftConfig.trackFrustrations = newValue }
        get { swiftConfig.trackFrustrations }
    }

    public var trackBackgroundEvents: Bool {
        set { swiftConfig.trackBackgroundEvents = newValue }
        get { swiftConfig.trackBackgroundEvents }
    }

    public var trackWatchdogTerminations: Bool {
        set { swiftConfig.trackWatchdogTerminations = newValue }
        get { swiftConfig.trackWatchdogTerminations }
    }

    public var longTaskThreshold: TimeInterval {
        set { swiftConfig.longTaskThreshold = newValue }
        get { swiftConfig.longTaskThreshold ?? 0 }
    }

    public var appHangThreshold: TimeInterval {
        set { swiftConfig.appHangThreshold = newValue == 0 ? nil : newValue }
        get { swiftConfig.appHangThreshold ?? 0 }
    }

    public var vitalsUpdateFrequency: objc_VitalsFrequency {
        set { swiftConfig.vitalsUpdateFrequency = newValue.swiftType }
        get { objc_VitalsFrequency(swiftType: swiftConfig.vitalsUpdateFrequency) }
    }

    public func setViewEventMapper(_ mapper: @escaping (objc_RUMViewEvent) -> objc_RUMViewEvent) {
        swiftConfig.viewEventMapper = { swiftEvent in
            let objcEvent = objc_RUMViewEvent(swiftModel: swiftEvent)
            return mapper(objcEvent).swiftModel
        }
    }

    public func setResourceEventMapper(_ mapper: @escaping (objc_RUMResourceEvent) -> objc_RUMResourceEvent?) {
        swiftConfig.resourceEventMapper = { swiftEvent in
            let objcEvent = objc_RUMResourceEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    public func setActionEventMapper(_ mapper: @escaping (objc_RUMActionEvent) -> objc_RUMActionEvent?) {
        swiftConfig.actionEventMapper = { swiftEvent in
            let objcEvent = objc_RUMActionEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    public func setErrorEventMapper(_ mapper: @escaping (objc_RUMErrorEvent) -> objc_RUMErrorEvent?) {
        swiftConfig.errorEventMapper = { swiftEvent in
            let objcEvent = objc_RUMErrorEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    public func setLongTaskEventMapper(_ mapper: @escaping (objc_RUMLongTaskEvent) -> objc_RUMLongTaskEvent?) {
        swiftConfig.longTaskEventMapper = { swiftEvent in
            let objcEvent = objc_RUMLongTaskEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    public var onSessionStart: ((String, Bool) -> Void)? {
        set { swiftConfig.onSessionStart = newValue }
        get { swiftConfig.onSessionStart }
    }

    public var customEndpoint: URL? {
        set { swiftConfig.customEndpoint = newValue }
        get { swiftConfig.customEndpoint }
    }

    public var trackAnonymousUser: Bool {
        set { swiftConfig.trackAnonymousUser = newValue }
        get { swiftConfig.trackAnonymousUser }
    }
}

@objc(DDRUM)
@objcMembers
@_spi(objc)
public class objc_RUM: NSObject {
    public static func enable(with configuration: objc_RUMConfiguration) {
        RUM.enable(with: configuration.swiftConfig)
    }
}

@objc(DDRUMMonitor)
@objcMembers
@_spi(objc)
public class objc_RUMMonitor: NSObject {
    // MARK: - Internal

    internal let swiftRUMMonitor: DatadogRUM.RUMMonitorProtocol

    internal init(swiftRUMMonitor: DatadogRUM.RUMMonitorProtocol) {
        self.swiftRUMMonitor = swiftRUMMonitor
    }

    // MARK: - Public

    public static func shared() -> objc_RUMMonitor {
        objc_RUMMonitor(swiftRUMMonitor: RUMMonitor.shared())
    }

    public func currentSessionID(completion: @escaping (String?) -> Void) {
        swiftRUMMonitor.currentSessionID(completion: completion)
    }

    public func stopSession() {
        swiftRUMMonitor.stopSession()
    }

    public func startView(
        viewController: UIViewController,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startView(viewController: viewController, name: name, attributes: attributes.dd.swiftAttributes)
    }

    public func stopView(
        viewController: UIViewController,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopView(viewController: viewController, attributes: attributes.dd.swiftAttributes)
    }

    public func startView(
        key: String,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startView(key: key, name: name, attributes: attributes.dd.swiftAttributes)
    }

    public func stopView(
        key: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopView(key: key, attributes: attributes.dd.swiftAttributes)
    }

    public func addTiming(name: String) {
        swiftRUMMonitor.addTiming(name: name)
    }

    public func addError(
        message: String,
        stack: String?,
        source: objc_RUMErrorSource,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addError(message: message, stack: stack, source: source.swiftType, attributes: attributes.dd.swiftAttributes)
    }

    public func addError(
        error: Error,
        source: objc_RUMErrorSource,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addError(error: error, source: source.swiftType, attributes: attributes.dd.swiftAttributes)
    }

    public func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResource(resourceKey: resourceKey, request: request, attributes: attributes.dd.swiftAttributes)
    }

    public func startResource(
        resourceKey: String,
        url: URL,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResource(resourceKey: resourceKey, url: url, attributes: attributes.dd.swiftAttributes)
    }

    public func startResource(
        resourceKey: String,
        httpMethod: objc_RUMMethod,
        urlString: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResource(resourceKey: resourceKey, httpMethod: httpMethod.swiftType, urlString: urlString, attributes: attributes.dd.swiftAttributes)
    }

    public func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addResourceMetrics(resourceKey: resourceKey, metrics: metrics, attributes: attributes.dd.swiftAttributes)
    }

    public func stopResource(
        resourceKey: String,
        response: URLResponse,
        size: NSNumber?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResource(resourceKey: resourceKey, response: response, size: size?.int64Value, attributes: attributes.dd.swiftAttributes)
    }

    public func stopResource(
        resourceKey: String,
        statusCode: NSNumber?,
        kind: objc_ResourceType,
        size: NSNumber?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResource(
            resourceKey: resourceKey,
            statusCode: statusCode?.intValue,
            kind: kind.swiftType,
            size: size?.int64Value,
            attributes: attributes.dd.swiftAttributes
        )
    }

    public func stopResourceWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceWithError(resourceKey: resourceKey, error: error, response: response, attributes: attributes.dd.swiftAttributes)
    }

    public func stopResourceWithError(
        resourceKey: String,
        message: String,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceWithError(resourceKey: resourceKey, message: message, response: response, attributes: attributes.dd.swiftAttributes)
    }

    public func startAction(
        type: objc_RUMActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startAction(type: type.swiftType, name: name, attributes: attributes.dd.swiftAttributes)
    }

    public func stopAction(
        type: objc_RUMActionType,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopAction(type: type.swiftType, name: name, attributes: attributes.dd.swiftAttributes)
    }

    public func addAction(
        type: objc_RUMActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addAction(type: type.swiftType, name: name, attributes: attributes.dd.swiftAttributes)
    }

    public func addAttribute(
        forKey key: String,
        value: Any
    ) {
        swiftRUMMonitor.addAttribute(forKey: key, value: AnyEncodable(value))
    }

    public func addAttributes(_ attributes: [String: Any]) {
        swiftRUMMonitor.addAttributes(attributes.dd.swiftAttributes)
    }

    public func removeAttribute(forKey key: String) {
        swiftRUMMonitor.removeAttribute(forKey: key)
    }

    public func removeAttributes(forKeys keys: [String]) {
        swiftRUMMonitor.removeAttributes(forKeys: keys)
    }

    public func addFeatureFlagEvaluation(name: String, value: Any) {
        swiftRUMMonitor.addFeatureFlagEvaluation(name: name, value: AnyEncodable(value))
    }

    public var debug: Bool {
        set { swiftRUMMonitor.debug = newValue }
        get { swiftRUMMonitor.debug }
    }
}
