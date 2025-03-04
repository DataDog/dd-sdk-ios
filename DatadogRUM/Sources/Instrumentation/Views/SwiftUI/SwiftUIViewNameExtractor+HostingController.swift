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
    internal func extractHostingControllerPath(with reflector: ReflectorType) -> String? {
        if let hostView = reflector.descendantIfPresent("host", "_rootView", "content", "storage", "view") {
            var output = ""
            dumper.dump(hostView, to: &output)
            return output
        }

        if let hostView = reflector.descendantIfPresent("host", "_rootView") {
            var output = ""
            dumper.dump(hostView, to: &output)
            return output
        }
        return nil
    }

    // MARK: - String Parsing
    @usableFromInline
    internal func extractViewNameFromHostingViewController(_ input: String) -> String? {
        // First pattern: Extract from generic format with angle brackets
        if let lastOpenBracket = input.lastIndex(of: "<"),
           let closingBracket = input[lastOpenBracket...].firstIndex(of: ">"),
           lastOpenBracket < closingBracket {
            var betweenBrackets = input[input.index(after: lastOpenBracket)..<closingBracket]

            // Handle generic parameters by taking the first part before comma
            betweenBrackets = betweenBrackets.split(separator: ",").first ?? betweenBrackets

            // Extract name after the first dot (to get the type name without namespace)
            if let fristDotIndex = betweenBrackets.firstIndex(of: ".") {
                let viewName = betweenBrackets[betweenBrackets.index(after: fristDotIndex)...]
                return String(viewName)
            }

            // If no dots found, return the whole content between brackets
            return String(betweenBrackets)
        }

        // Second pattern: Extract from format with parentheses at the end
        // Example: "MyApp.(unknown context at $10cc64f58).(unknown context at $10cc64f64).HomeView()"
        if input.hasSuffix("()") {
            // Find the last component before the parentheses
            let withoutParens = input.dropLast(2)

            // Get the last component after a dot
            if let lastDotIndex = withoutParens.lastIndex(of: ".") {
                let viewName = withoutParens[withoutParens.index(after: lastDotIndex)...]
                return String(viewName)
            }
        }

        return nil
    }
}
