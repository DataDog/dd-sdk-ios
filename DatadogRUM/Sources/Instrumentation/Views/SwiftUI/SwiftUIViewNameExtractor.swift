/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

// MARK: - SwiftUIViewNameExtractor
/// Protocol defining interface for extracting view names for SwiftUI views
internal protocol SwiftUIViewNameExtractor {
    func extractName(from: UIViewController) -> String?
}

// MARK: - SwiftUIReflectionBasedViewNameExtractor
/// Default implementation that extracts SwiftUI view names using reflection and string parsing
internal struct SwiftUIReflectionBasedViewNameExtractor: SwiftUIViewNameExtractor {
    private let createReflector: (Any) -> TopLevelReflector

    init(
        reflectorFactory: @escaping (Any) -> TopLevelReflector = { subject in
            ReflectionMirror(reflecting: subject)
        }
    ) {
        self.createReflector = reflectorFactory
    }

    /// Attempts to extract a meaningful SwiftUI view name from a `UIViewController`
    /// - Parameter viewController: The `UIViewController` potentially hosting a SwiftUI view
    /// - Returns: The extracted view name or `nil`
    func extractName(from viewController: UIViewController) -> String? {
        // We ignore UIKit container view controllers
        if Bundle(for: type(of: viewController)).dd.isUIKit {
            return nil
        }

        // Skip known container controllers that shouldn't be tracked
        let className = NSStringFromClass(type(of: viewController))

        if shouldSkipViewController(viewController: viewController, className: className) {
            return nil
        }

        let controllerType = ControllerType(from: className)

        // Reflector to inspect the view controller's internals
        let reflector = createReflector(viewController)

        return extractViewName(
            from: viewController,
            controllerType: controllerType,
            withReflector: reflector
        )
    }

    private func extractViewName(
        from viewController: UIViewController,
        controllerType: ControllerType,
        withReflector reflector: TopLevelReflector
    ) -> String? {
        switch controllerType {
        case .hostingController:
            if let output = SwiftUIViewPath.hostingControllerRootView.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

            if let output = SwiftUIViewPath.hostingControllerModifiedContent.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

            // TODO: RUM-9892 - Implement more robust fallback identifiers
            if SwiftUIViewPath.hostingControllerBase.traverse(with: reflector) != nil {
                return extractFallbackViewName(from: typeDescription(of: viewController))
            }

        case .navigationStackHostingController:
            if let output = SwiftUIViewPath.navigationStackContent.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

            // TODO: RUM-9892 - Implement more robust fallback identifiers
            if SwiftUIViewPath.navigationStackAnyView.traverse(with: reflector) != nil {
                return extractFallbackViewName(from: typeDescription(of: viewController))
            }

            if let output = SwiftUIViewPath.navigationStackBase.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

        case .modal:
            if let output = SwiftUIViewPath.sheetContent.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

        case .unknown:
            break
        }

        return nil
    }

    // MARK: - Helpers
    private static let genericTypePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"<(?:[^,>]*,\s+)?([^<>,]+?)>"#)
    }()

    private static let hostingControllerPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "UIHostingController<([A-Za-z0-9_]+)>")
    }()

    private static let navigationStackPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "NavigationStackHostingController<([A-Za-z0-9_]+)>")
    }()

    /// Extracts a view name from a type description
    internal func extractViewName(from input: String) -> String? {
        // Extract the view name from generic types like ParameterizedLazyView<String, DetailView>
        if let match = Self.genericTypePattern?.firstMatch(
            in: input,
            options: [],
            range: NSRange(input.startIndex..<input.endIndex, in: input)
        ),
           let range = Range(match.range(at: 1), in: input) {
            return String(input[range])
        }

        // Extract the view name from metatypes like DetailView.Type
        else if input.hasSuffix(".Type") {
            return String(input.dropLast(5))
        }

        // If the input is already a simple view name (no brackets, parentheses, etc.)
        // and looks like a valid SwiftUI view name pattern
        else if input.range(of: "^[A-Z][A-Za-z0-9_]*View$", options: .regularExpression) != nil {
            return input
        }

        return nil
    }

    private static let HostingControllerFallbackViewName = "AutoTracked_HostingController_Fallback"
    private static let NavigationStackControllerFallbackViewName = "AutoTracked_NavigationStackController_Fallback"

    /// Extracts a fallback view name when reflection-based extraction fails.
    /// This method attempts to extract a reasonable name from the controller's description
    /// when our primary reflection-based methods cannot identify the hosted SwiftUI view.
    internal func extractFallbackViewName(from viewControllerDescription: String) -> String {
        // For generic `AnyView` containers, return the full description as it's
        // already the most informative name available
        if viewControllerDescription == "NavigationStackHostingController<AnyView>" || viewControllerDescription == "UIHostingController<AnyView>" {
            return viewControllerDescription
        }

        // For UIHostingController<SomeView>, extract `SomeView` as the name
        if let viewName = extractGenericViewName(from: viewControllerDescription, using: Self.hostingControllerPattern) {
            return viewName
        }

        // For NavigationStackHostingController<SomeView>, extract `SomeView` as the name
        if let viewName = extractGenericViewName(from: viewControllerDescription, using: Self.navigationStackPattern) {
            return viewName
        }

        // When no specific view name can be extracted,
        // return a generic fallback name based on the controller type
        return viewControllerDescription.contains("UIHostingController") ? Self.HostingControllerFallbackViewName : Self.NavigationStackControllerFallbackViewName
    }

    private func extractGenericViewName(from description: String, using pattern: NSRegularExpression?) -> String? {
        guard let pattern else {
            return nil
        }

        if let match = pattern.firstMatch(
            in: description,
            options: [],
            range: NSRange(description.startIndex..<description.endIndex, in: description)
        ),
           let range = Range(match.range(at: 1), in: description) {
            return String(description[range])
        }

        return nil
    }

    internal func shouldSkipViewController(viewController: UIViewController, className: String) -> Bool {
        // Skip TabBar controllers
        if className == "SwiftUI.UIKitTabBarController" {
            return true
        }

        if className == "_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_" {
            return true
        }

        if className == "SwiftUI.TabHostingController" {
            return true
        }

        // Skip Navigation controllers
        if viewController is UINavigationController {
            return true
        }

        if className == "SwiftUI.NotifyingMulticolumnSplitViewController" {
            return true
        }

        return false
    }

    private func typeDescription(of object: Any) -> String {
        return String(describing: type(of: object))
    }
}
