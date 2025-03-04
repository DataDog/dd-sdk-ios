/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

extension SwiftUIReflectionBasedViewNameExtractor {
    // MARK: - Path Traversal
    @usableFromInline
    internal func extractNavigationControllerPath(reflector: ReflectorType) -> String? {
        // List / Navigation Split detailed pattern
        if let navStack = reflector.descendantIfPresent("host", "_rootView", "storage", "view", "content", "content", "content", "content", "list", "item", "type") {
            var output = ""
            dumper.dump(navStack, to: &output)
            return extractViewNameFromNavigationStackHostingController(output)
        }

        // Navigation Stack container: we ignore it
        if reflector.descendantIfPresent("host", "_rootView", "storage", "view", "content", "content", "content", "root") != nil {
            // TD - Check if we need this when closing detail/nav view
            return nil
        }

        // Standard Navigation Stack
        if let navStack = reflector.descendantIfPresent("host", "_rootView", "storage", "view", "content", "content", "content") {
            var output = ""
            dumper.dump(navStack, to: &output)
            return extractViewNameFromNavigationStackHostingController(output)
        }

        return nil
    }

    // MARK: - String Parsing
    @usableFromInline
    internal func extractViewNameFromNavigationStackHostingController(_ input: String) -> String? {
        print("intput:\n")
        print(input)
        // e.g., AppName.DetailView.self
        if input.hasSuffix(".self") {
            let components = input.components(separatedBy: ".")
            if components.count >= 2 {
                return components[components.count - 2]
            }
        }

        // Generic type pattern: SwiftUI.ParameterizedLazyView<Swift.String, SwiftUITest.DetailViewForNavigationDestination>
        if let lastOpenBracket = input.lastIndex(of: "<"),
           let closingBracket = input[lastOpenBracket...].firstIndex(of: ">") {
            // Extract content between the last angle brackets
            var betweenBrackets = input[input.index(after: lastOpenBracket)..<closingBracket]

            // Take the last component in case of multiple generic parameters
            betweenBrackets = betweenBrackets.split(separator: ",").last ?? betweenBrackets

            // Extract name after the first dot (to get the type name without namespace)
            if let fristDotIndex = betweenBrackets.firstIndex(of: ".") {
                let viewName = betweenBrackets[betweenBrackets.index(after: fristDotIndex)...]
                return String(viewName)
            }

            // If no dots found, return the whole content between brackets
            return String(betweenBrackets)
        }

        // Direct view instantiation (no brackets)
        if let dotIndex = input.firstIndex(of: "."),
           let endIndex = input[dotIndex...].firstIndex(where: { $0 == "(" }),
           dotIndex < endIndex {
            return String(input[input.index(after: dotIndex)..<endIndex])
        }

        // Built-in SwiftUI views
        if input.hasPrefix("SwiftUI.") {
            if let dotIndex = input.firstIndex(of: "."),
               let endIndex = input[dotIndex...].firstIndex(where: { $0 == "(" }),
               dotIndex < endIndex {
                return String(input[input.index(after: dotIndex)..<endIndex])
            }
        }

        // Bracket-based extraction as fallback
        if let lastOpenBracket = input.lastIndex(of: "<"),
           let closingBracket = input[lastOpenBracket...].firstIndex(of: ">"),
           lastOpenBracket < closingBracket {
            let betweenBrackets = input[input.index(after: lastOpenBracket)..<closingBracket]

            if let dotIndex = betweenBrackets.firstIndex(of: ".") {
                let afterDot = betweenBrackets[dotIndex...].dropFirst()

                if let endIndex = afterDot.firstIndex(where: { $0 == "(" || $0 == "<" || $0 == "?" || $0 == "." }) {
                    return String(afterDot[..<endIndex])
                }
                return String(afterDot)
            }
        }

        return nil
    }
}
