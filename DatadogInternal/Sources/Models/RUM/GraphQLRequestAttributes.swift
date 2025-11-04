/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// GraphQL request attributes extracted from the request.
public struct GraphQLRequestAttributes: Equatable {
    /// GraphQL operation name.
    public let operationName: String?

    /// GraphQL operation type.
    public let operationType: String?

    /// GraphQL variables.
    public let variables: String?

    /// GraphQL payload.
    public let payload: String?

    /// Initializes a `GraphQLRequestAttributes` instance with the provided parameters.
    ///
    /// - Parameters:
    ///   - operationName: GraphQL operation name, if any.
    ///   - operationType: GraphQL operation type, if any.
    ///   - variables: GraphQL variables, if any.
    ///   - payload: GraphQL payload, if any.
    public init(
        operationName: String? = nil,
        operationType: String? = nil,
        variables: String? = nil,
        payload: String? = nil
    ) {
        self.operationName = operationName
        self.operationType = operationType
        self.variables = variables
        self.payload = payload
    }
}
