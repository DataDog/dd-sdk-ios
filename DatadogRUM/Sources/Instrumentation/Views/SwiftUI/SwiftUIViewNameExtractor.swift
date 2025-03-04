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
    internal let createReflector: (Any) -> ReflectorType
    internal let dumper: Dumper

    init(
        reflectorFactory: @escaping (Any) -> ReflectorType = { subject in
            Reflector(subject: subject, telemetry: NOPTelemetry())
        },
        dumper: Dumper = DefaultDumper()
    ) {
        self.createReflector = reflectorFactory
        self.dumper = dumper
    }

    /// Attempts to extract a meaningful SwiftUI view name from a UIViewController
    /// - Parameter viewController: The UIViewController potentially hosting a SwiftUI view
    /// - Returns: The extracted view name or nil if extraction failed
    func extractName(from viewController: UIViewController) -> String? {
        return extractViewNameFrom(from: viewController)
    }

    private func extractViewNameFrom(from viewController: UIViewController) -> String? {
        // Reflector to inspect the view controller's internals
        let reflector = createReflector(viewController)

        // Get the class name to determine the view controller type
        let className = NSStringFromClass(type(of: viewController))

        // Skip known container controllers that shouldn't be tracked
        if shouldSkipViewController(className: className, viewController: viewController) {
            return nil
        }

        // Detect the view controller type based on class name
        let controllerType = detectControllerType(className: className)

        // Extract view name based on controller type
        return extractViewName(
            from: viewController,
            withReflector: reflector,
            controllerType: controllerType
        )
    }

    internal func extractViewName(
        from viewController: UIViewController,
        withReflector reflector: ReflectorType,
        controllerType: ControllerType
    ) -> String? {
        switch controllerType {
        case .tabItem:
            return extractTabViewName(viewController: viewController)

        case .hostingController:
            if let output = extractHostingControllerPath(with: reflector) {
                return extractViewNameFromHostingViewController(output)
            }

        case .navigationController:
            return extractNavigationControllerPath(reflector: reflector)

        case .modal:
            if let output = extractSheetContentPath(with: reflector) {
                return extractViewNameFromSheetContent(output)
            }

        case .unknown:
            break
        }

        return nil
    }

    // MARK: - Helpers
    internal func shouldSkipViewController(className: String, viewController: UIViewController) -> Bool {
        // Skip Tab Bar Controllers as they're containers
        if className == "SwiftUI.UIKitTabBarController" {
            return true
        }

        // Skip Navigation Controllers
        if viewController is UINavigationController {
            return true
        }

        return false
    }

    /// Controller type enum to identify different SwiftUI hosting controllers
    internal enum ControllerType {
        case hostingController
        case navigationController
        case modal
        case tabItem
        case unknown
    }

    /// Determines the controller type from the class name
    internal func detectControllerType(className: String) -> ControllerType {
        if className.contains("_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_") {
            return .tabItem
        } else if className.contains("TtGC7SwiftUI19UIHostingController") {
            return .hostingController
        } else if className.contains("Navigation") {
            return .navigationController
        } else if className.contains("_TtGC7SwiftUI29PresentationHostingController") {
            return .modal
        }

        return .unknown
    }
}

// MARK: - ReflectorType
/// Protocol defining an interface for reflection-based object inspection.
/// `ReflectorType` provides a consistent way to navigate through object structures
/// by traversing paths of properties.
internal protocol ReflectorType {
    /// Attempts to find a descendant at the specified path.
    func descendantIfPresent(_ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) -> Any?
}

extension Reflector: ReflectorType {}
