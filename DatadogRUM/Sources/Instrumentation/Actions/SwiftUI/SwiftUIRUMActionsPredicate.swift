/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Predicate determining which SwiftUI component interactions should be recorded as RUM actions.
/// Implement this protocol to customize or filter SwiftUI action tracking.
public protocol SwiftUIRUMActionsPredicate {
    /// The predicate deciding if the RUM Action should be recorded.
    /// - Parameter componentName: The name of the SwiftUI component that received the action
    /// - Returns: RUM Action if it should be recorded, `nil` otherwise.
    func rumAction(with componentName: String) -> RUMAction?
}
