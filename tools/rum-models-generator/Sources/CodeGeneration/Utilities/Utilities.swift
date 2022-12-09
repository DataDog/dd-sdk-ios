/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

public struct Exception: Error, CustomStringConvertible {
    public let description: String

    init(
        _ reason: String,
        file: StaticString,
        line: UInt
    ) {
        // `file` includes slash-separated path, take only the last component:
        let fileName = "\(file)".split(separator: "/").last ?? "\(file)"
        let sourceReference = "🧭 Thrown in \(fileName):\(line)"

        self.description = "\(reason)\n\n\(sourceReference)"
    }

    public static func inconsistency(_ reason: String, file: StaticString = #fileID, line: UInt = #line) -> Exception {
        Exception("🐞 Inconsistency: \"\(reason)\".", file: file, line: line)
    }

    public static func illegal(_ operation: String, file: StaticString = #fileID, line: UInt = #line) -> Exception {
        Exception("⛔️ Illegal operation: \"\(operation)\".", file: file, line: line)
    }

    public static func unimplemented(_ operation: String, file: StaticString = #fileID, line: UInt = #line) -> Exception {
        Exception("🚧 Unimplemented: \"\(operation)\".", file: file, line: line)
    }

    static func moreContext(_ moreContext: String, for error: Error, file: StaticString = #fileID, line: UInt = #line) -> Exception {
        if let decodingError = error as? DecodingError {
            return Exception(
                """
                ⬇️
                🛑 \(moreContext)

                🔎 Pretty error: \(pretty(error: decodingError))

                ⚙️ Original error: \(decodingError)
                """,
                file: file,
                line: line
            )
        } else {
            return Exception(
                """
                ⬇️
                🛑 \(moreContext)

                ⚙️ Original error: \(error)
                """,
                file: file,
                line: line
            )
        }
    }
}

public extension Optional {
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

extension Array where Element: Hashable {
    func asSet() -> Set<Element> {
        return Set(self)
    }
}

internal func withErrorContext<T>(context: String, block: () throws -> T) throws -> T {
    do {
        return try block()
    } catch let error {
        throw Exception.moreContext(context, for: error)
    }
}

// MARK: - `Swift.DecodingError` pretty formatting

/// Returns pretty description of given `DecodingError`.
private func pretty(error: DecodingError) -> String {
    var description = "✋ description is unavailable"
    var context: DecodingError.Context?

    switch error {
    case .typeMismatch(let type, let moreContext):
        description = "Type \(type) could not be decoded because it did not match the type of what was found in the encoded payload."
        context = moreContext
    case .valueNotFound(let type, let moreContext):
        description = "Non-optional value of type \(type) was expected, but a null value was found."
        context = moreContext
    case .keyNotFound(let key, let moreContext):
        description = "A keyed decoding container was asked for an entry for key \(key), but did not contain one."
        context = moreContext
    case .dataCorrupted(let moreContext):
        context = moreContext
    @unknown default:
        break
    }

    return "\n→ \(description)" + (context.flatMap { pretty(context: $0) } ?? "")
}

/// Returns pretty description of given `DecodingError.Context`.
private func pretty(context: DecodingError.Context) -> String {
    let codingPath: [String] = context.codingPath.map { codingKey in
        if let intValue = codingKey.intValue {
            return String(intValue)
        } else {
            return codingKey.stringValue
        }
    }
    return """

    → In Context:
        → coding path: \(codingPath.joined(separator: " → "))
        → underlyingError: \(String(describing: context.underlyingError))
    """
}

// MARK: - String formatting

public extension String {
    var camelCased: String {
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
