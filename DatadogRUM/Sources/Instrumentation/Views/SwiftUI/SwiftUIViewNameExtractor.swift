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
    internal let createReflector: (Any) -> TopLevelReflector

    init(
        reflectorFactory: @escaping (Any) -> TopLevelReflector = { subject in
            Reflector(
                subject: subject,
                // MARK: TODO: RUM-9035 - Telemetry
                telemetry: NOPTelemetry()
            )
        }
    ) {
        self.createReflector = reflectorFactory
    }

    /// Attempts to extract a meaningful SwiftUI view name from a UIViewController
    /// - Parameter viewController: The `UIViewController` potentially hosting a SwiftUI view
    /// - Returns: The extracted view name or nil if extraction failed
    func extractName(from viewController: UIViewController) -> String? {
        return extractViewNameFrom(from: viewController)
    }

    private func extractViewNameFrom(from viewController: UIViewController) -> String? {
        // Skip known container controllers that shouldn't be tracked
        if shouldSkipViewController(viewController: viewController) {
            return nil
        }

        // Reflector to inspect the view controller's internals
        let reflector = createReflector(viewController)

        return extractViewName(
            from: viewController,
            withReflector: reflector
        )
    }

    internal func extractViewName(
        from viewController: UIViewController,
        withReflector reflector: TopLevelReflector
    ) -> String? {
        let className = NSStringFromClass(type(of: viewController))
        let controllerType = ControllerType(className: className)

        switch controllerType {
        case .tabItem:
            return extractTabViewName(viewController: viewController)

        case .hostingController:
            if let output = SwiftUIViewPath.hostingController.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

        case .navigationController:
            // Try detail view first
            if let output = SwiftUIViewPath.navigationStackDetail.traverse(with: reflector) {
                return extractViewName(from: typeDescription(of: output))
            }

            // Check if it's a container view that we should ignore
            if SwiftUIViewPath.navigationStackContainer.traverse(with: reflector) != nil {
                return nil
            }

            // Try standard navigation stack view
            if let output = SwiftUIViewPath.navigationStack.traverse(with: reflector) {
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
    /// Extracts a view name from a type description using regex patterns
    internal func extractViewName(from input: String) -> String? {
        // Pattern 1: Extract the view name from generic types like LazyView<ContentView>
        let simpleGenericPattern = #"<([^<>,]+)>"#
        if let match = input.range(of: simpleGenericPattern, options: .regularExpression) {
            let startIndex = input.index(match.lowerBound, offsetBy: 1)
            let endIndex = input.index(match.upperBound, offsetBy: -1)
            return String(input[startIndex..<endIndex])
        }

        // Pattern 2: Extract the view name from complex generic types like ParameterizedLazyView<String, DetailView>
        let complexGenericPattern = #"<.*,\s*([^<>,]+)>"#
        if let match = input.range(of: complexGenericPattern, options: .regularExpression),
           let captureRange = input.range(of: #"([^<>,]+)(?=>)"#, options: .regularExpression, range: match) {
            return String(input[captureRange]).trimmingCharacters(in: .whitespaces)
        }

        // Pattern 3: Extract the view name from metatypes like DetailView.Type
        if input.hasSuffix(".Type") {
            return String(input.dropLast(5))
        }

        // Return the input as a fallback
        return input
    }

    internal func extractTabViewName(viewController: UIViewController) -> String? {
        // We fetch the parent, which corresponds to the TabBarController
        guard let parent = viewController.parent as? UITabBarController,
              let container = parent.parent else {
            return nil
        }

        let selectedIndex = parent.selectedIndex
        let containerReflector = Reflector(subject: container, telemetry: NOPTelemetry())

        if let output = SwiftUIViewPath.hostingController.traverse(with: containerReflector) {
            let typeName = typeDescription(of: output)
            if let containerViewName = extractViewName(from: typeName) {
                return "\(containerViewName)_index_\(selectedIndex)"
            }
        }

        return nil
    }

    internal func shouldSkipViewController(viewController: UIViewController) -> Bool {
        // Skip Tab Bar Controllers as they're containers
        if viewController is UITabBarController {
            return true
        }

        // Skip Navigation Controllers
        if viewController is UINavigationController {
            return true
        }

        return false
    }

    private func typeDescription(of object: Any) -> String {
        return String(describing: type(of: object))
    }
}
