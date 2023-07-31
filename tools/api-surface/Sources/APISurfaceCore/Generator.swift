/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SourceKittenFramework

private typealias DocsDictionary = [String: Any]

internal enum AccessLevel: String {
    case `private` = "source.lang.swift.accessibility.private"
    case `fileprivate` = "source.lang.swift.accessibility.fileprivate"
    case `internal` = "source.lang.swift.accessibility.internal"
    case `public` = "source.lang.swift.accessibility.public"
    case `open` = "source.lang.swift.accessibility.open"
}

/// A single API interface item, e.g.: class or method declaration.
internal struct SurfaceItem {
    /// Declaration of this item as it appears in the code, e.g. `class Car` or `case manufacturer1` for enum.
    let declaration: String
    /// The access level of this item (or `nil` if it couldn't be inferred by SourceKitten).
    let accessLevel: AccessLevel?
    /// The nesting level of this item determined by number of ancestor items.
    let nestingLevel: Int
    /// Current generation context for this item.
    let childItems: [SurfaceItem]
}

internal class Generator {
    private struct Context {
        var nestingLevel: Int = 0
    }

    /// Tracks currently traversed items.
    private var items: [SurfaceItem] = []

    func generateSurfaceItems(for module: Module) throws -> [SurfaceItem] {
        items = []
        for docs in module.docs {
            guard let dictionaries = (docs.docsDictionary as [String: Any]).substructure else {
                throw APISurfaceError(description: "Could not find `SourceKitten.substructure` in file: \(docs.file.path ?? "")")
            }
            items.append(contentsOf: traverse(dictionaries: dictionaries, context: Context()))
        }
        return flatten(rootItems: items)
    }

    // MARK: - Traverse

    private func traverse(dictionaries: [DocsDictionary], context: Context) -> [SurfaceItem] {
        return dictionaries.flatMap {
            traverse(dictionary: $0, context: context)
        }
    }

    private func traverse(dictionary: DocsDictionary, context: Context) -> [SurfaceItem] {
        if let declaration = dictionary.parsedDeclaration {
            let singleItem = SurfaceItem(
                declaration: declaration,
                accessLevel: dictionary.accessLevel,
                nestingLevel: context.nestingLevel,
                childItems: {
                    if let substructure = dictionary.substructure {
                        var nextContext = context
                        nextContext.nestingLevel += 1
                        return traverse(dictionaries: substructure, context: nextContext)
                    } else {
                        return []
                    }
                }()
            )
            return [singleItem]
        } else if let substructure = dictionary.substructure {
            let multipleItems = traverse(dictionaries: substructure, context: context)
            return multipleItems
        }

        return []
    }

    // MARK: - Flatten

    private func flatten(rootItems: [SurfaceItem]) -> [SurfaceItem] {
        func flattenRecursively(nextItem: SurfaceItem, result: inout [SurfaceItem]) {
            result.append(nextItem)
            for child in nextItem.childItems {
                flattenRecursively(nextItem: child, result: &result)
            }
        }

        var result: [SurfaceItem] = []
        for item in rootItems {
            flattenRecursively(nextItem: item, result: &result)
        }
        return result
    }
}

private extension Dictionary where Key == String, Value == Any {
    var accessLevel: AccessLevel? {
        (self["key.accessibility"] as? String).flatMap { AccessLevel(rawValue: $0) }
    }

    var parsedDeclaration: String? {
        self["key.parsed_declaration"] as? String
    }

    var substructure: [DocsDictionary]? {
        self["key.substructure"] as? [DocsDictionary]
    }
}

extension Optional where Wrapped == AccessLevel {
    var isPublic: Bool {
        switch self {
        case .some(let wrapped): return wrapped == .public || wrapped == .open
        case .none: return false
        }
    }
}
