/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// MARK: - SwiftUI Views Predicate Bridge

internal struct SwiftUIRUMViewsPredicateBridge: SwiftUIRUMViewsPredicate {
    let objcPredicate: objc_SwiftUIRUMViewsPredicate

    func rumView(for extractedViewName: String) -> RUMView? {
        return objcPredicate.rumView(for: extractedViewName)?.swiftView
    }
}

@objc(DDSwiftUIRUMViewsPredicate)
@_spi(objc)
public protocol objc_SwiftUIRUMViewsPredicate: AnyObject {
    /// The predicate deciding if the RUM View should be tracked or dropped for given SwiftUI view name.
    /// - Parameter extractedViewName: The name of the SwiftUI view detected by the SDK.
    /// - Returns: RUM View parameters if the view should be tracked, `nil` otherwise.
    func rumView(for extractedViewName: String) -> objc_RUMView?
}

@objc(DDDefaultSwiftUIRUMViewsPredicate)
@_spi(objc)
public class objc_DefaultSwiftUIRUMViewsPredicate: NSObject, objc_SwiftUIRUMViewsPredicate {
    private let swiftPredicate = DefaultSwiftUIRUMViewsPredicate()

    public func rumView(for extractedViewName: String) -> objc_RUMView? {
        return swiftPredicate.rumView(for: extractedViewName).map {
            objc_RUMView(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
}

// MARK: - SwiftUI Actions Predicate Bridge

internal struct SwiftUIRUMActionsPredicateBridge: SwiftUIRUMActionsPredicate {
    let objcPredicate: objc_SwiftUIRUMActionsPredicate

    func rumAction(with componentName: String) -> RUMAction? {
        return objcPredicate.rumAction(with: componentName)?.swiftAction
    }
}

@objc(DDSwiftUIRUMActionsPredicate)
@_spi(objc)
public protocol objc_SwiftUIRUMActionsPredicate: AnyObject {
    /// The predicate deciding if the RUM Action should be tracked or dropped.
    /// - Parameter componentName: The name of the SwiftUI component that received the action
    /// - Returns: RUM Action if it should be tracked, `nil` otherwise.
    func rumAction(with componentName: String) -> objc_RUMAction?
}

@objc(DDDefaultSwiftUIRUMActionsPredicate)
@_spi(objc)
public class objc_DefaultSwiftUIRUMActionsPredicate: NSObject, objc_SwiftUIRUMActionsPredicate {
    private let swiftPredicate: DefaultSwiftUIRUMActionsPredicate

    public init(isLegacyDetectionEnabled: Bool) {
        swiftPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: isLegacyDetectionEnabled)
        super.init()
    }

    override public convenience init() {
        self.init(isLegacyDetectionEnabled: true)
    }

    public func rumAction(with componentName: String) -> objc_RUMAction? {
        swiftPredicate.rumAction(with: componentName).map {
            objc_RUMAction(name: $0.name, attributes: $0.attributes.dd.objCAttributes)
        }
    }
}
