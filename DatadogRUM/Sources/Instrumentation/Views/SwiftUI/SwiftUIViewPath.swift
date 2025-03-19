/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Common path components for SwiftUI view traversal
internal enum SwiftUIViewNode: String {
    case host
    case rootView = "_rootView"
    case root
    case storage
    case view
    case content
    case list
    case item
    case type

    static let hostingBase: [SwiftUIViewNode] = [.host, .rootView]
    static let navigationBase: [SwiftUIViewNode] = [.host, .rootView, .storage, .view, .content, .content, .content]
    static let sheetBase: [SwiftUIViewNode] = [.host, .rootView, .storage, .view, .content]
}

/// Defines the various traversal paths for different SwiftUI view structures
///
/// This enum provides a structured way to navigate SwiftUI's internal view hierarchy
/// through reflection.
internal enum SwiftUIViewPath {
    case hostingController
    case hostingControllerRoot
    case navigationStack
    case navigationStackDetail
    case navigationStackContainer
    case sheetContent

    /// The sequence of property names to traverse for this view type
    var pathComponents: [SwiftUIViewNode] {
        switch self {
        case .hostingController:
            return SwiftUIViewNode.hostingBase + [.content, .storage, .view]
        case .hostingControllerRoot:
            return SwiftUIViewNode.hostingBase
        case .navigationStack:
            return SwiftUIViewNode.navigationBase
        case .navigationStackDetail:
            return SwiftUIViewNode.navigationBase + [.content, .list, .item, .type]
        case .navigationStackContainer:
            return SwiftUIViewNode.navigationBase + [.root]
        case .sheetContent:
            return SwiftUIViewNode.sheetBase
        }
    }

    /// Traverses the path with the given reflector to extract view information
    ///
    /// - Parameter reflector: The reflector object used to traverse the view hierarchy
    /// - Returns: The object found at the end of the path, or nil if not found
    func traverse(with reflector: TopLevelReflector) -> Any? {
        // Convert string components to path objects
        let paths = pathComponents.map { ReflectionMirror.Path.key($0.rawValue) }

        // Use descendant directly
        return reflector.descendant(paths)
    }
}
