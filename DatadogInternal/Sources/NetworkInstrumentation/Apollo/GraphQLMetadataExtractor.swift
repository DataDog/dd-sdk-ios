/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import Foundation
import Apollo
@_spi(Internal)
@_spi(Unsafe)
import ApolloAPI

/// Utility for extracting GraphQL operation metadata for monitoring purposes.
internal struct GraphQLMetadataExtractor {
    /// Extracts variables from a GraphQL operation using Apollo's built-in JSON encoding.
    /// - Parameter operation: The GraphQL operation to extract variables from
    /// - Returns: JSON string representation of the variables, or nil if extraction fails
    internal func extractVariables<T: GraphQLOperation>(from operation: T) -> String? {
        let variables = operation.__variables ?? [:]

        guard !variables.isEmpty else {
            return nil
        }

        // Convert each variable to its _jsonValue representation to ensure JSON-serializability.
        // We use _jsonValue instead of _jsonEncodableObject to properly handle types like
        // GraphQLEnum that need conversion before serialization.
        let jsonValueDict = variables.mapValues { variableValue -> Any in
            // Use _jsonEncodableValue to get the JSONEncodable, then extract _jsonValue
            if let jsonValue = variableValue._jsonEncodableValue?._jsonValue {
                return jsonValue
            }
            // Fallback to string representation to preserve semantic information
            return String(describing: variableValue)
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonValueDict, options: [])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            // If serialization fails, return nil to avoid breaking the request
            return nil
        }
    }

    /// Extracts the operation type from a GraphQL operation.
    /// - Parameter operation: The GraphQL operation to analyze
    /// - Returns: The operation type string (query, mutation, subscription), or nil if unknown
    internal func extractOperationType<T: GraphQLOperation>(from operation: T) -> String? {
        let operationType = T.operationType
        switch operationType {
        case .query:
            return "query"
        case .mutation:
            return "mutation"
        case .subscription:
            return "subscription"
        @unknown default:
            return nil
        }
    }

    /// Extracts the full GraphQL operation query as a payload.
    /// - Parameter operation: The GraphQL operation to extract payload from
    /// - Returns: JSON string representation of the operation payload, or nil if extraction fails
    internal func extractPayload<T: GraphQLOperation>(from operation: T) -> String? {
        let operationDocument = T.operationDocument

        if let queryDocument = operationDocument.definition?.queryDocument, !queryDocument.isEmpty {
           return queryDocument
        }

        return nil
    }
}
#endif
