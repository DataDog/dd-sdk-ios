/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

internal struct Printer {
    func print(items: [SurfaceItem]) -> String {
        var lines: [String] = []

        for item in items {
            let line = format(declaration: item.declaration, nestingLevel: item.nestingLevel)

            if isPublic(item) {
                lines.append(line)
            } else if hasPublicDescendant(item) {
                // This means we don't know the access level of this item, but we know
                // it has public descendant items. In such case, we print the item into
                // the surface file but prefix with `[?]` for human verification.
                lines.append("[?] " + line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func isPublic(_ item: SurfaceItem) -> Bool {
        switch item.accessLevel {
        case .public, .open: return true
        default: return false
        }
    }

    private func hasPublicDescendant(_ item: SurfaceItem) -> Bool {
        for child in item.childItems {
            return isPublic(child) ? true : hasPublicDescendant(child)
        }
        return false
    }
}

internal func format(declaration: String, nestingLevel: Int) -> String {
    let inlinedDeclaration = declaration
        .split(separator: "\n")
        .map { String($0).removingCommonLeadingWhitespaceFromLines() }
        .joined()
    let indentation = (0..<nestingLevel).map({ _ in "    " }).joined()
    return "\(indentation)\(inlinedDeclaration)"
}
