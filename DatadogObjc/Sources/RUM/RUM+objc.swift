/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogInternal
import DatadogRUM

internal struct UIKitRUMViewsPredicateBridge: UIKitRUMViewsPredicate {
    let objcPredicate: DDUIKitRUMViewsPredicate

    func rumView(for viewController: UIViewController) -> RUMView? {
        return objcPredicate.rumView(for: viewController)?.swiftView
    }
}

@objc
public class DDRUMView: NSObject {
    let swiftView: RUMView

    @objc public var name: String { swiftView.name }
    @objc public var attributes: [String: Any] { castAttributesToObjectiveC(swiftView.attributes) }

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - name: the RUM View name, appearing as `VIEW NAME` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    @objc
    public init(name: String, attributes: [String: Any]) {
        swiftView = RUMView(
            name: name,
            attributes: castAttributesToSwift(attributes)
        )
    }
}

@objc
public protocol DDUIKitRUMViewsPredicate: AnyObject {
    /// The predicate deciding if the RUM View should be started or ended for given instance of the `UIViewController`.
    /// - Parameter viewController: an instance of the view controller noticed by the SDK.
    /// - Returns: RUM View parameters if received view controller should start/end the RUM View, `nil` otherwise.
    func rumView(for viewController: UIViewController) -> DDRUMView?
}

@objc
public class DDDefaultUIKitRUMViewsPredicate: NSObject, DDUIKitRUMViewsPredicate {
    private let swiftPredicate = DefaultUIKitRUMViewsPredicate()

    public func rumView(for viewController: UIViewController) -> DDRUMView? {
        return swiftPredicate.rumView(for: viewController).map {
            DDRUMView(name: $0.name, attributes: castAttributesToObjectiveC($0.attributes))
        }
    }
}

@objc
public class DDDefaultUIKitRUMActionsPredicate: NSObject, DDUIKitRUMActionsPredicate {
    let swiftPredicate = DefaultUIKitRUMActionsPredicate()
    #if os(tvOS)
    public func rumAction(press type: UIPress.PressType, targetView: UIView) -> DDRUMAction? {
        swiftPredicate.rumAction(press: type, targetView: targetView).map {
            DDRUMAction(name: $0.name, attributes: castAttributesToObjectiveC($0.attributes))
        }
    }
    #else
    public func rumAction(targetView: UIView) -> DDRUMAction? {
        swiftPredicate.rumAction(targetView: targetView).map {
            DDRUMAction(name: $0.name, attributes: castAttributesToObjectiveC($0.attributes))
        }
    }
    #endif
}

internal struct UIKitRUMActionsPredicateBridge: UITouchRUMActionsPredicate & UIPressRUMActionsPredicate {
    let objcPredicate: AnyObject?

    init(objcPredicate: DDUITouchRUMActionsPredicate) {
        self.objcPredicate = objcPredicate
    }

    init(objcPredicate: DDUIPressRUMActionsPredicate) {
        self.objcPredicate = objcPredicate
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        guard let objcPredicate = objcPredicate as? DDUITouchRUMActionsPredicate else {
            return nil
        }
        return objcPredicate.rumAction(targetView: targetView)?.swiftAction
    }

    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        guard let objcPredicate = objcPredicate as? DDUIPressRUMActionsPredicate else {
            return nil
        }
        return objcPredicate.rumAction(press: type, targetView: targetView)?.swiftAction
    }
}

@objc
public class DDRUMAction: NSObject {
    let swiftAction: RUMAction

    @objc public var name: String { swiftAction.name }
    @objc public var attributes: [String: Any] { castAttributesToObjectiveC(swiftAction.attributes) }

    /// Initializes the RUM Action description.
    /// - Parameters:
    ///   - name: the RUM Action name, appearing as `ACTION NAME` in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM Action.
    @objc
    public init(name: String, attributes: [String: Any]) {
        swiftAction = RUMAction(
            name: name,
            attributes: castAttributesToSwift(attributes)
        )
    }
}

#if os(tvOS)
@objc
public protocol DDUIKitRUMActionsPredicate: DDUIPressRUMActionsPredicate {}
#else
@objc
public protocol DDUIKitRUMActionsPredicate: DDUITouchRUMActionsPredicate {}
#endif

@objc
public protocol DDUITouchRUMActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: UIView) -> DDRUMAction?
}

@objc
public protocol DDUIPressRUMActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameters:
    ///   - type: the `UIPress.PressType` which received the action.
    ///   - targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(press type: UIPress.PressType, targetView: UIView) -> DDRUMAction?
}

@objc
public enum DDRUMErrorSource: Int {
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

@objc
public enum DDRUMActionType: Int {
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

@objc
public enum DDRUMResourceType: Int {
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

@objc
public enum DDRUMMethod: Int {
    case post
    case get
    case head
    case put
    case delete
    case patch

    internal var swiftType: RUMMethod {
        switch self {
        case .post: return .post
        case .get: return .get
        case .head: return .head
        case .put: return .put
        case .delete: return .delete
        case .patch: return .patch
        default: return .get
        }
    }
}

@objc
public enum DDRUMVitalsFrequency: Int {
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

@objc
public class DDRUMFirstPartyHostsTracing: NSObject {
    internal var swiftType: RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing

    @objc
    public init(hostsWithHeaderTypes: [String: Set<DDTracingHeaderType>]) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in Set(headerTypes.map { $0.swiftType }) }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders)
    }

    @objc
    public init(hostsWithHeaderTypes: [String: Set<DDTracingHeaderType>], sampleRate: Float) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in Set(headerTypes.map { $0.swiftType }) }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders, sampleRate: sampleRate)
    }

    @objc
    public init(hosts: Set<String>) {
        swiftType = .trace(hosts: hosts)
    }

    @objc
    public init(hosts: Set<String>, sampleRate: Float) {
        swiftType = .trace(hosts: hosts, sampleRate: sampleRate)
    }
}

@objc
public class DDRUMURLSessionTracking: NSObject {
    internal var swiftConfig: RUM.Configuration.URLSessionTracking

    @objc
    override public init() {
        swiftConfig = .init()
    }

    @objc
    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: DDRUMFirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }

    @objc
    public func setResourceAttributesProvider(_ provider: @escaping (URLRequest, URLResponse?, Data?, Error?) -> [String: Any]?) {
        swiftConfig.resourceAttributesProvider = { request, response, data, error in
            let objcAttributes = provider(request, response, data, error)
            return objcAttributes.map { castAttributesToSwift($0) }
        }
    }
}

@objc
public class DDRUMConfiguration: NSObject {
    internal var swiftConfig: DatadogRUM.RUM.Configuration

    @objc
    public init(applicationID: String) {
        swiftConfig = .init(applicationID: applicationID)
    }

    @objc public var applicationID: String {
        swiftConfig.applicationID
    }

    @objc public var sessionSampleRate: Float {
        set { swiftConfig.sessionSampleRate = newValue }
        get { swiftConfig.sessionSampleRate }
    }

    @objc public var telemetrySampleRate: Float {
        set { swiftConfig.telemetrySampleRate = newValue }
        get { swiftConfig.telemetrySampleRate }
    }

    @objc public var uiKitViewsPredicate: DDUIKitRUMViewsPredicate? {
        set { swiftConfig.uiKitViewsPredicate = newValue.map { UIKitRUMViewsPredicateBridge(objcPredicate: $0) } }
        get { (swiftConfig.uiKitViewsPredicate as? UIKitRUMViewsPredicateBridge)?.objcPredicate  }
    }

    @objc public var uiKitActionsPredicate: DDUIKitRUMActionsPredicate? {
        set { swiftConfig.uiKitActionsPredicate = newValue.map { UIKitRUMActionsPredicateBridge(objcPredicate: $0) } }
        get { (swiftConfig.uiKitActionsPredicate as? UIKitRUMActionsPredicateBridge)?.objcPredicate as? DDUIKitRUMActionsPredicate  }
    }

    @objc
    public func setURLSessionTracking(_ tracking: DDRUMURLSessionTracking) {
        swiftConfig.urlSessionTracking = tracking.swiftConfig
    }

    @objc public var trackFrustrations: Bool {
        set { swiftConfig.trackFrustrations = newValue }
        get { swiftConfig.trackFrustrations }
    }

    @objc public var trackBackgroundEvents: Bool {
        set { swiftConfig.trackBackgroundEvents = newValue }
        get { swiftConfig.trackBackgroundEvents }
    }

    @objc public var longTaskThreshold: TimeInterval {
        set { swiftConfig.longTaskThreshold = newValue }
        get { swiftConfig.longTaskThreshold ?? 0 }
    }

    @objc public var vitalsUpdateFrequency: DDRUMVitalsFrequency {
        set { swiftConfig.vitalsUpdateFrequency = newValue.swiftType }
        get { DDRUMVitalsFrequency(swiftType: swiftConfig.vitalsUpdateFrequency) }
    }

    @objc
    public func setViewEventMapper(_ mapper: @escaping (DDRUMViewEvent) -> DDRUMViewEvent) {
        swiftConfig.viewEventMapper = { swiftEvent in
            let objcEvent = DDRUMViewEvent(swiftModel: swiftEvent)
            return mapper(objcEvent).swiftModel
        }
    }

    @objc
    public func setResourceEventMapper(_ mapper: @escaping (DDRUMResourceEvent) -> DDRUMResourceEvent?) {
        swiftConfig.resourceEventMapper = { swiftEvent in
            let objcEvent = DDRUMResourceEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func setActionEventMapper(_ mapper: @escaping (DDRUMActionEvent) -> DDRUMActionEvent?) {
        swiftConfig.actionEventMapper = { swiftEvent in
            let objcEvent = DDRUMActionEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func setErrorEventMapper(_ mapper: @escaping (DDRUMErrorEvent) -> DDRUMErrorEvent?) {
        swiftConfig.errorEventMapper = { swiftEvent in
            let objcEvent = DDRUMErrorEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc
    public func setLongTaskEventMapper(_ mapper: @escaping (DDRUMLongTaskEvent) -> DDRUMLongTaskEvent?) {
        swiftConfig.longTaskEventMapper = { swiftEvent in
            let objcEvent = DDRUMLongTaskEvent(swiftModel: swiftEvent)
            return mapper(objcEvent)?.swiftModel
        }
    }

    @objc public var onSessionStart: ((String, Bool) -> Void)? {
        set { swiftConfig.onSessionStart = newValue }
        get { swiftConfig.onSessionStart }
    }

    @objc public var customEndpoint: URL? {
        set { swiftConfig.customEndpoint = newValue }
        get { swiftConfig.customEndpoint }
    }
}

@objc
public class DDRUM: NSObject {
    @objc
    public static func enable(with configuration: DDRUMConfiguration) {
        RUM.enable(with: configuration.swiftConfig)
    }
}

@objc
public class DDRUMMonitor: NSObject {
    // MARK: - Internal

    internal let swiftRUMMonitor: DatadogRUM.RUMMonitorProtocol

    internal init(swiftRUMMonitor: DatadogRUM.RUMMonitorProtocol) {
        self.swiftRUMMonitor = swiftRUMMonitor
    }

    // MARK: - Public

    @objc
    public static func shared() -> DDRUMMonitor {
        DDRUMMonitor(swiftRUMMonitor: RUMMonitor.shared())
    }

    @objc
    public func startView(
        viewController: UIViewController,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startView(viewController: viewController, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopView(
        viewController: UIViewController,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopView(viewController: viewController, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startView(
        key: String,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startView(key: key, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopView(
        key: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopView(key: key, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addTiming(name: String) {
        swiftRUMMonitor.addTiming(name: name)
    }

    @objc
    public func addError(
        message: String,
        stack: String?,
        source: DDRUMErrorSource,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addError(message: message, stack: stack, source: source.swiftType, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addError(
        error: Error,
        source: DDRUMErrorSource,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addError(error: error, source: source.swiftType, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResource(resourceKey: resourceKey, request: request, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startResource(
        resourceKey: String,
        url: URL,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResource(resourceKey: resourceKey, url: url, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startResource(
        resourceKey: String,
        httpMethod: DDRUMMethod,
        urlString: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResource(resourceKey: resourceKey, httpMethod: httpMethod.swiftType, urlString: urlString, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addResourceMetrics(resourceKey: resourceKey, metrics: metrics, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopResource(
        resourceKey: String,
        response: URLResponse,
        size: NSNumber?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResource(resourceKey: resourceKey, response: response, size: size?.int64Value, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopResource(
        resourceKey: String,
        statusCode: NSNumber?,
        kind: DDRUMResourceType,
        size: NSNumber?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResource(
            resourceKey: resourceKey,
            statusCode: statusCode?.intValue,
            kind: kind.swiftType,
            size: size?.int64Value,
            attributes: castAttributesToSwift(attributes)
        )
    }

    @objc
    public func stopResourceWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceWithError(resourceKey: resourceKey, error: error, response: response, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopResourceWithError(
        resourceKey: String,
        message: String,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceWithError(resourceKey: resourceKey, message: message, response: response, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startAction(
        type: DDRUMActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopAction(
        type: DDRUMActionType,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addAction(
        type: DDRUMActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addAttribute(
        forKey key: String,
        value: Any
    ) {
        swiftRUMMonitor.addAttribute(forKey: key, value: AnyEncodable(value))
    }

    @objc
    public func removeAttribute(forKey key: String) {
        swiftRUMMonitor.removeAttribute(forKey: key)
    }
}
