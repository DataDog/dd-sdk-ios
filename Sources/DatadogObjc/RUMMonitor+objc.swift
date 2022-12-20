/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import struct Datadog.DDAnyEncodable
import class Datadog.DDRUMMonitor
import class Datadog.RUMMonitor
import enum Datadog.RUMErrorSource
import enum Datadog.RUMUserActionType
import typealias Datadog.RUMResourceType
import enum Datadog.RUMMethod
import struct Datadog.RUMView
import protocol Datadog.UIKitRUMViewsPredicate
import struct Datadog.RUMAction
import protocol Datadog.UITouchRUMUserActionsPredicate
import protocol Datadog.UIPressRUMUserActionsPredicate

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

internal struct UIKitRUMUserActionsPredicateBridge: UITouchRUMUserActionsPredicate & UIPressRUMUserActionsPredicate {
    let objcPredicate: AnyObject?

    init(objcPredicate: DDUITouchRUMUserActionsPredicate) {
        self.objcPredicate = objcPredicate
    }

    init(objcPredicate: DDUIPressRUMUserActionsPredicate) {
        self.objcPredicate = objcPredicate
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        guard let objcPredicate = objcPredicate as? DDUITouchRUMUserActionsPredicate else {
            return nil
        }
        return objcPredicate.rumAction(targetView: targetView)?.swiftAction
    }

    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        guard let objcPredicate = objcPredicate as? DDUIPressRUMUserActionsPredicate else {
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
public protocol DDUIKitRUMUserActionsPredicate: DDUIPressRUMUserActionsPredicate {}
#else
@objc
public protocol DDUIKitRUMUserActionsPredicate: DDUITouchRUMUserActionsPredicate {}
#endif

@objc
public protocol DDUITouchRUMUserActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter targetView: an instance of the `UIView` which received the action.
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(targetView: UIView) -> DDRUMAction?
}

@objc
public protocol DDUIPressRUMUserActionsPredicate: AnyObject {
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
public enum DDRUMUserActionType: Int {
    case tap
    case scroll
    case swipe
    case custom

    internal var swiftType: RUMUserActionType {
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
public class DDRUMMonitor: NSObject {
    // MARK: - Internal

    internal let swiftRUMMonitor: Datadog.DDRUMMonitor

    internal init(swiftRUMMonitor: Datadog.DDRUMMonitor) {
        self.swiftRUMMonitor = swiftRUMMonitor
    }

    // MARK: - Public

    @objc
    override public convenience init() {
        self.init(swiftRUMMonitor: RUMMonitor.initialize())
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
        source: DDRUMErrorSource,
        stack: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addError(message: message, source: source.swiftType, stack: stack, attributes: castAttributesToSwift(attributes))
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
    public func startResourceLoading(
        resourceKey: String,
        request: URLRequest,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResourceLoading(resourceKey: resourceKey, request: request, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startResourceLoading(
        resourceKey: String,
        url: URL,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResourceLoading(resourceKey: resourceKey, url: url, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startResourceLoading(
        resourceKey: String,
        httpMethod: DDRUMMethod,
        urlString: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startResourceLoading(resourceKey: resourceKey, httpMethod: httpMethod.swiftType, urlString: urlString, attributes: castAttributesToSwift(attributes))
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
    public func stopResourceLoading(
        resourceKey: String,
        response: URLResponse,
        size: NSNumber?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceLoading(resourceKey: resourceKey, response: response, size: size?.int64Value, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopResourceLoading(
        resourceKey: String,
        statusCode: NSNumber?,
        kind: DDRUMResourceType,
        size: NSNumber?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceLoading(
            resourceKey: resourceKey,
            statusCode: statusCode?.intValue,
            kind: kind.swiftType,
            size: size?.int64Value,
            attributes: castAttributesToSwift(attributes)
        )
    }

    @objc
    public func stopResourceLoadingWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceLoadingWithError(resourceKey: resourceKey, error: error, response: response, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopResourceLoadingWithError(
        resourceKey: String,
        errorMessage: String,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopResourceLoadingWithError(resourceKey: resourceKey, errorMessage: errorMessage, response: response, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func startUserAction(
        type: DDRUMUserActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.startUserAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func stopUserAction(
        type: DDRUMUserActionType,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.stopUserAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addUserAction(
        type: DDRUMUserActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor.addUserAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    @objc
    public func addAttribute(
        forKey key: String,
        value: Any
    ) {
        swiftRUMMonitor.addAttribute(forKey: key, value: DDAnyEncodable(value))
    }

    @objc
    public func removeAttribute(forKey key: String) {
        swiftRUMMonitor.removeAttribute(forKey: key)
    }
}
