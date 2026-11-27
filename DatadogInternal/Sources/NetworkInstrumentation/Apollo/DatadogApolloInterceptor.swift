/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import Foundation
import Apollo
@_spi(Unsafe)
import ApolloAPI

/// Apollo interceptor that adds Datadog GraphQL monitoring headers to outgoing requests.
///
/// This interceptor extracts GraphQL operation metadata (name, type, variables, payload)
/// and adds them as HTTP headers that can be consumed by Datadog RUM monitoring.
///
/// - Note: This interceptor is compatible with Apollo iOS 2.0+ which uses structured concurrency.
public struct DatadogApolloInterceptor: GraphQLInterceptor {
    /// Whether to include the full GraphQL payload in headers
    private let sendGraphQLPayloads: Bool

    /// Utility for extracting operation metadata
    private let metadataExtractor = GraphQLMetadataExtractor()

    /// Initializes the interceptor.
    /// - Parameters:
    ///   - sendGraphQLPayloads: Whether to include the full GraphQL operation payload in headers. Defaults to false.
    public init(sendGraphQLPayloads: Bool = false) {
        self.sendGraphQLPayloads = sendGraphQLPayloads
    }

    /// Intercepts the Apollo request and adds Datadog GraphQL monitoring headers.
    /// - Parameters:
    ///   - request: The GraphQL request to process
    ///   - next: The next interceptor function to call
    /// - Returns: The stream of parsed results
    public func intercept<Request: GraphQLRequest>(
        request: Request,
        next: NextInterceptorFunction<Request>
    ) async throws -> InterceptorResultStream<Request> {
        // Extract operation metadata
        var modifiedRequest = request
        let operation = request.operation
        let operationName = type(of: operation).operationName
        let operationType = metadataExtractor.extractOperationType(from: operation)
        let operationVariables = metadataExtractor.extractVariables(from: operation)

        // Add GraphQL operation name header
        modifiedRequest.addHeader(name: GraphQLHeaders.operationName, value: operationName)

        // Add GraphQL operation type header if available
        if let operationType = operationType {
            modifiedRequest.addHeader(name: GraphQLHeaders.operationType, value: operationType)
        }

        // Add GraphQL variables header if available
        if let operationVariables = operationVariables {
            modifiedRequest.addHeader(name: GraphQLHeaders.variables, value: operationVariables)
        }

        // Add GraphQL payload header if enabled and available
        if sendGraphQLPayloads {
            if let operationPayload = metadataExtractor.extractPayload(from: operation) {
                modifiedRequest.addHeader(name: GraphQLHeaders.payload, value: operationPayload)
            }
        }

        // Continue with the modified request
        return await next(modifiedRequest)
    }
}
#endif
