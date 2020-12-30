/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit
import class Datadog.DDRUMMonitor
import class Datadog.RUMMonitor
import enum Datadog.RUMErrorSource
import enum Datadog.RUMUserActionType
import struct Datadog.RUMView
import protocol Datadog.UIKitRUMViewsPredicate

internal struct PredicateBridge: UIKitRUMViewsPredicate {
    let objcPredicate: DDUIKitRUMViewsPredicate
    func rumView(for viewController: UIViewController) -> RUMView? {
        return objcPredicate.rumView(for: viewController)?.swiftView
    }
}

@objcMembers
public class DDRUMView: NSObject {
    let swiftView: RUMView

    public var path: String { swiftView.path }
    public var attributes: [String: Any] { swiftView.attributes }

    /// Initializes the RUM View description.
    /// - Parameters:
    ///   - path: the RUM View path, appearing as "PATH" in RUM Explorer.
    ///   - attributes: additional attributes to associate with the RUM View.
    public init(path: String, attributes: [String: Any]) {
        swiftView = RUMView(
            path: path,
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
public enum DDRUMErrorSource: Int {
    /// Error originated in the source code.
    case source
    /// Error originated in the network layer.
    case network
    /// Error originated in a webview.
    case webview
    /// Custom error source.
    case custom

    fileprivate var swiftType: RUMErrorSource {
        switch self {
        case .source: return .source
        case .network: return .network
        case .webview: return .webview
        case .custom: return .custom
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

    fileprivate var swiftType: RUMUserActionType {
        switch self {
        case .tap: return .tap
        case .scroll: return .scroll
        case .swipe: return .swipe
        case .custom: return .custom
        default: return .custom
        }
    }
}

internal let noopRUMMonitor = DatadogObjc.DDRUMMonitor(swiftRUMMonitor: nil)

@objcMembers
public class DDRUMMonitor: NSObject {
    // MARK: - Internal

    internal let swiftRUMMonitor: Datadog.DDRUMMonitor?

    internal init(swiftRUMMonitor: Datadog.DDRUMMonitor?) {
        self.swiftRUMMonitor = swiftRUMMonitor
    }

    // MARK: - Public

    override public convenience init() {
        self.init(swiftRUMMonitor: RUMMonitor.initialize())
    }

    public func startView(
        viewController: UIViewController,
        path: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.startView(viewController: viewController, path: path, attributes: castAttributesToSwift(attributes))
    }

    public func stopView(
        viewController: UIViewController,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.stopView(viewController: viewController, attributes: castAttributesToSwift(attributes))
    }

    public func addTiming(name: String) {
        swiftRUMMonitor?.addTiming(name: name)
    }

    public func addError(
        error: Error,
        source: DDRUMErrorSource,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.addError(error: error, source: source.swiftType, attributes: castAttributesToSwift(attributes))
    }

    public func startResourceLoading(
        resourceKey: String,
        request: URLRequest,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.startResourceLoading(resourceKey: resourceKey, request: request, attributes: castAttributesToSwift(attributes))
    }

    public func startResourceLoading(
        resourceKey: String,
        url: URL,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.startResourceLoading(resourceKey: resourceKey, url: url, attributes: castAttributesToSwift(attributes))
    }

    public func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.addResourceMetrics(resourceKey: resourceKey, metrics: metrics, attributes: castAttributesToSwift(attributes))
    }

    public func stopResourceLoading(
        resourceKey: String,
        response: URLResponse,
        size: Int64?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.stopResourceLoading(resourceKey: resourceKey, response: response, size: size, attributes: castAttributesToSwift(attributes))
    }

    public func stopResourceLoadingWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.stopResourceLoadingWithError(resourceKey: resourceKey, error: error, response: response, attributes: castAttributesToSwift(attributes))
    }

    public func stopResourceLoadingWithError(
        resourceKey: String,
        errorMessage: String,
        response: URLResponse?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.stopResourceLoadingWithError(resourceKey: resourceKey, errorMessage: errorMessage, response: response, attributes: castAttributesToSwift(attributes))
    }

    public func startUserAction(
        type: DDRUMUserActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.startUserAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    public func stopUserAction(
        type: DDRUMUserActionType,
        name: String?,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.stopUserAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    public func addUserAction(
        type: DDRUMUserActionType,
        name: String,
        attributes: [String: Any]
    ) {
        swiftRUMMonitor?.addUserAction(type: type.swiftType, name: name, attributes: castAttributesToSwift(attributes))
    }

    public func addAttribute(
        forKey key: String,
        value: Any
    ) {
        swiftRUMMonitor?.addAttribute(forKey: key, value: AnyEncodable(value))
    }

    public func removeAttribute(forKey key: String) {
        swiftRUMMonitor?.removeAttribute(forKey: key)
    }
}
