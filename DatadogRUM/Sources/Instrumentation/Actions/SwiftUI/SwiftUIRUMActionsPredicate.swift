/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

/// Predicate determining which SwiftUI component interactions should be recorded as RUM actions.
/// Implement this protocol to customize or filter SwiftUI action tracking.
public protocol SwiftUIRUMActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter componentName: The name of the SwiftUI component that received the action
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(with componentName: String) -> RUMAction?
}

/// Default implementations of `SwiftUIRUMActionsPredicate`
public struct DefaultSwiftUIRUMActionsPredicate {
    /// Whether to enable SwiftUI action detection on iOS 17 and below.
    /// When set to `false`, actions will only be detected on iOS 18+ where the detection is more reliable.
    /// Defaults to `true` for backward compatibility.
    private let isLegacyDetectionEnabled: Bool

    /// Creates a default SwiftUI RUM actions predicate.
    /// - Parameter isLegacyDetectionEnabled: Whether to enable SwiftUI action detection on iOS 17 and below.
    ///                                     Set to `false` to only use the more reliable iOS 18+ detection.
    public init(isLegacyDetectionEnabled: Bool = true) {
        self.isLegacyDetectionEnabled = isLegacyDetectionEnabled
    }
}

// MARK: DefaultSwiftUIRUMActionsPredicate
extension DefaultSwiftUIRUMActionsPredicate: SwiftUIRUMActionsPredicate {
    public func rumAction(with componentName: String) -> RUMAction? {
        if #available(iOS 18.0, *) {
            return RUMAction(name: componentName, attributes: [:])
        } else if isLegacyDetectionEnabled {
            return RUMAction(name: componentName, attributes: [:])
        }
        return nil
    }
}
