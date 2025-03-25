/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Protocol defining the predicate for SwiftUI view tracking in RUM.
///
/// The SDK uses this predicate to determine whether a detected SwiftUI view should be tracked as a RUM view.
/// When a SwiftUI view is detected, the SDK first extracts its name,
/// then passes that name to this predicate to convert it into RUM view parameters or filter it out.
///
/// Implement this protocol to customize which SwiftUI views are tracked and how they appear in the RUM Explorer.
public protocol SwiftUIRUMViewsPredicate {
    /// Converts an extracted SwiftUI view name into RUM view parameters, or filters it out.
    ///
    /// - Parameter extractedViewName: The name of the SwiftUI view detected by the SDK.
    /// - Returns: RUM view parameters if the view should be tracked, or `nil` to ignore the view.
    func rumView(for extractedViewName: String) -> RUMView?
}

/// Default implementation of `SwiftUIRUMViewsPredicate`.
///
/// This implementation tracks all detected SwiftUI views with their extracted names.
/// The view name in RUM Explorer will match the name extracted from the SwiftUI view.
public struct DefaultSwiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicate {
    public init() {}

    public func rumView(for extractedViewName: String) -> RUMView? {
        return RUMView(name: extractedViewName)
    }
}
