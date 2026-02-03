/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// MARK: - GraphQL Response Models

/// Lightweight decoder to check if a GraphQL response contains errors.
/// Only checks for the presence of the "errors" key without decoding the entire array.
internal struct GraphQLResponseHasErrors: Decodable {
    let hasErrors: Bool
    private enum CodingKeys: String, CodingKey { case errors }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasErrors = container.contains(.errors)
    }
}

/// Represents a GraphQL error in the response.
///
/// Note: Some GraphQL implementations may include `code` at the error level (legacy pattern)
/// instead of within `extensions.code`. Both locations are supported for compatibility.
/// Reference: https://spec.graphql.org/September2025/#note-5c13b
internal struct GraphQLResponseError: Decodable {
    let message: String
    let locations: [GraphQLResponseErrorLocation]?
    let path: [GraphQLResponsePathElement]?
    let extensions: Extensions?

    /// Error code extracted from either `extensions.code` (preferred) or top-level `code` (legacy).
    var code: String? {
        return extensions?.code ?? legacyCode
    }

    /// Legacy code field that some implementations put at the error level instead of in extensions.
    private let legacyCode: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case locations
        case path
        case extensions
        case legacyCode = "code"
    }

    /// GraphQL error extensions. Only the `code` field is extracted as it's the most commonly used.
    /// The GraphQL spec allows any additional fields in extensions, but we focus on error codes.
    struct Extensions: Decodable {
        let code: String?
    }
}

/// Represents a location in a GraphQL query where an error occurred.
internal struct GraphQLResponseErrorLocation: Decodable {
    let line: Int
    let column: Int
}

/// Represents an element in the path to a field that caused an error.
internal enum GraphQLResponsePathElement: Decodable {
    case string(String)
    case int(Int)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Path element must be string or int"
            )
        }
    }
}
