/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

internal struct Exception: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    static func inconsistency(_ reason: String) -> Exception {
        Exception("🐞 Inconsistency: \"\(reason)\".")
    }

    static func illegal(_ operation: String) -> Exception {
        Exception("⛔️ Illegal operation: \"\(operation)\".")
    }

    static func unimplemented(_ operation: String) -> Exception {
        Exception("🚧 Unimplemented: \"\(operation)\".")
    }

    static func moreContext(_ moreContext: String, for error: Error) -> Exception {
        Exception("🛑 \"\(moreContext)\". Original error: \(error)")
    }
}

internal extension Optional {
    func unwrapOrThrow(_ exception: Exception) throws -> Wrapped {
        switch self {
        case .some(let unwrappedValue):
            return unwrappedValue
        case .none:
            throw exception
        }
    }

    func ifNotNil<T>(_ closure: (Wrapped) throws -> T) rethrows -> T? {
        if case .some(let unwrappedValue) = self {
            return try closure(unwrappedValue)
        } else {
            return nil
        }
    }
}

extension String {
    private var camelCased: String {
        guard !isEmpty else {
            return ""
        }

        let words = components(separatedBy: CharacterSet.alphanumerics.inverted)
        let first = words.first! // swiftlint:disable:this force_unwrapping
        let rest = words.dropFirst().map { $0.uppercasingFirst }
        return ([first] + rest).joined(separator: "")
    }

    /// Uppercases the first character.
    var uppercasingFirst: String { prefix(1).uppercased() + dropFirst() }
    /// Lowercases the first character.
    var lowercasingFirst: String { prefix(1).lowercased() + dropFirst() }

    /// "lowerCamelCased" notation.
    var lowerCamelCased: String { camelCased.lowercasingFirst }
    /// "UpperCamelCased" notation.
    var upperCamelCased: String { camelCased.uppercasingFirst }
}

extension Array where Element: Hashable {
    func asSet() -> Set<Element> {
        return Set(self)
    }
} 

func withErrorContext<T>(context: String, block: () throws -> T) throws -> T {
    do {
        return try block()
    } catch let error {
        throw Exception.moreContext(context, for: error)
    }
}
