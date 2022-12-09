/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import SourceKittenFramework

/// Finds public `InterfaceItems` in given `SwiftDocs`.
internal func getPublicInterfaceItems(from docs: SwiftDocs) throws -> [InterfaceItem] {
    let docsJSONObject = toNSDictionary(docs.docsDictionary)
    let docsJSONData = try JSONSerialization.data(
        withJSONObject: docsJSONObject,
        options: [.prettyPrinted, .sortedKeys]
    )

    let skCode = try decoder.decode(SKCode.self, from: docsJSONData)

    var items: [InterfaceItem] = []
    recursivelySearchForPublicInterfaceItems(in: skCode.substructures, result: &items)
    return items
}

// MARK: - Parsing SourceKitten-generated documentation

/// Decodable `SourceKitten's` representation of a file documentation.
private class SKCode: Decodable {
    enum CodingKeys: String, CodingKey {
        case substructures = "key.substructure"
    }

    let substructures: [SKSubstructure]
}

/// Decodable `SourceKitten's` representation of a code construct documentation.
/// Code construct may nest other code constructs.
private class SKSubstructure: Decodable {
    enum CodingKeys: String, CodingKey {
        case accessibility  = "key.accessibility"
        case declaration    = "key.parsed_declaration"
        case substructures  = "key.substructure"
    }

    /// e.g. `source.lang.swift.accessibility.public`
    let accessibility: String?
    /// e.g. `public class Car`
    let declaration: String?
    let substructures: [SKSubstructure]?
}

private let decoder = JSONDecoder()

/// Inspects `SKCode` and fills the `result` array with public `InterfaceItems`.
private func recursivelySearchForPublicInterfaceItems(
    in skSubstructures: [SKSubstructure],
    result: inout [InterfaceItem],
    recursionLevel: Int = 0
) {
    skSubstructures
        .compactMap { $0 }
        .forEach { structure in
            if structure.accessibility == "source.lang.swift.accessibility.public" {
                if let declaration = structure.declaration {
                    let item = InterfaceItem(
                        declaration: declaration,
                        nestingLevel: recursionLevel
                    )
                    result.append(item)
                }
            }

            /// Some `substructures` parsed by `SourceKitten` are simple containers without any declaration.
            let hasDeclaration = structure.declaration != nil

            if let substructures = structure.substructures {
                // Structures can nest other structures, e.g. `enum` may nest
                // its `case` substructures. We do head recursion to
                // list them in the correct order.
                recursivelySearchForPublicInterfaceItems(
                    in: substructures,
                    result: &result,
                    recursionLevel: recursionLevel + (hasDeclaration ? 1 : 0)
                )
            }
        }
}
