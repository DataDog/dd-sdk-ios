/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogRUM
import DatadogInternal

// MARK: - SwiftUI Views Predicate Bridge

internal struct SwiftUIRUMViewsPredicateBridge: SwiftUIRUMViewsPredicate {
    let objcPredicate: DDSwiftUIRUMViewsPredicate

    func rumView(for extractedViewName: String) -> RUMView? {
        return objcPredicate.rumView(for: extractedViewName)?.swiftView
    }
}

@objc
public protocol DDSwiftUIRUMViewsPredicate: AnyObject {
    /// The predicate deciding if the RUM View should be tracked or dropped for given SwiftUI view name.
    /// - Parameter extractedViewName: The name of the SwiftUI view detected by the SDK.
    /// - Returns: RUM View parameters if the view should be tracked, `nil` otherwise.
    func rumView(for extractedViewName: String) -> DDRUMView?
}

@objc
public class DDDefaultSwiftUIRUMViewsPredicate: NSObject, DDSwiftUIRUMViewsPredicate {
    private let swiftPredicate = DefaultSwiftUIRUMViewsPredicate()

    public func rumView(for extractedViewName: String) -> DDRUMView? {
        return swiftPredicate.rumView(for: extractedViewName).map {
            DDRUMView(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
}

// MARK: - SwiftUI Actions Predicate Bridge

internal struct SwiftUIRUMActionsPredicateBridge: SwiftUIRUMActionsPredicate {
    let objcPredicate: DDSwiftUIRUMActionsPredicate

    func rumAction(with componentName: String) -> RUMAction? {
        return objcPredicate.rumAction(with: componentName)?.swiftAction
    }
}

@objc
public protocol DDSwiftUIRUMActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be tracked or dropped.
    /// - Parameter componentName: The name of the SwiftUI component that received the action
    /// - Returns: RUM Action if it should be tracked, `nil` otherwise.
    func rumAction(with componentName: String) -> DDRUMAction?
}

@objc
public class DDDefaultSwiftUIRUMActionsPredicate: NSObject, DDSwiftUIRUMActionsPredicate {
    private let swiftPredicate: DefaultSwiftUIRUMActionsPredicate

    @objc(initWithIsLegacyDetectionEnabled:)
    public init(isLegacyDetectionEnabled: Bool) {
        swiftPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: isLegacyDetectionEnabled)
        super.init()
    }

    public func rumAction(with componentName: String) -> DDRUMAction? {
        return swiftPredicate.rumAction(with: componentName).map {
            DDRUMAction(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
}
