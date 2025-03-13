/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Common path components for SwiftUI view traversal
internal enum RootPath {
    static let hostingBase = ["host", "_rootView"]
    static let navigationBase = ["host", "_rootView", "storage", "view", "content", "content", "content"]
    static let sheetBase = ["host", "_rootView", "storage", "view", "content"]
}

/// Defines the various traversal paths for different SwiftUI view structures
///
/// This enum provides a structured way to navigate SwiftUI's internal view hierarchy
/// through reflection.
internal enum SwiftUIViewPath {
    case hostingController
    case navigationStack
    case navigationStackDetail
    case navigationStackContainer
    case sheetContent

    /// The sequence of property names to traverse for this view type
    var pathComponents: [String] {
        switch self {
        case .hostingController:
            return RootPath.hostingBase + ["content", "storage", "view"]
        case .navigationStack:
            return RootPath.navigationBase
        case .navigationStackDetail:
            return RootPath.navigationBase + ["content", "list", "item", "type"]
        case .navigationStackContainer:
            return RootPath.navigationBase + ["root"]
        case .sheetContent:
            return RootPath.sheetBase
        }
    }

    /// Traverses the path with the given reflector to extract view information
    ///
    /// - Parameter reflector: The reflector object used to traverse the view hierarchy
    /// - Returns: The object found at the end of the path, or nil if not found
    func traverse(with reflector: TopLevelReflector) -> Any? {
        // Convert string components to path objects
        let paths = pathComponents.map { ReflectionMirror.Path.key($0) }

        // Use descendant directly
        return reflector.descendant(paths)
    }
}
