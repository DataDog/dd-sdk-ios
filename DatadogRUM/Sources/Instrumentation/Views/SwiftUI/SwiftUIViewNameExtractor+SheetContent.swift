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
    internal func extractSheetContentPath(with reflector: ReflectorType) -> String? {
        if let modalView = reflector.descendantIfPresent("host", "_rootView", "storage", "view", "content") {
            var output = ""
            dumper.dump(modalView, to: &output)
            return output
        }
        return nil
    }

    // MARK: - String Parsing
    @usableFromInline
    internal func extractViewNameFromSheetContent(_ input: String) -> String? {
        if input.contains("SheetContent<") {
            if let start = input.range(of: "SheetContent<")?.upperBound,
               let end = input[start...].firstIndex(of: "."),
               start < end,
               let viewEnd = input[end...].firstIndex(where: { $0 == "(" || $0 == ">" || $0 == "_" }) {
                return String(input[end..<viewEnd].dropFirst())
            }
        }
        return nil
    }
}
