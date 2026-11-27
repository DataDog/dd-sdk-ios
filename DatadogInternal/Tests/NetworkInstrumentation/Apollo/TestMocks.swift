/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import Foundation
@_spi(Execution)
@_spi(Unsafe)
@preconcurrency import ApolloAPI

// MARK: - Mock Data Structures

/// Mock schema for testing
internal enum MockSchema: SchemaMetadata {
    static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
        return ApolloAPI.Object(typename: typename, implementedInterfaces: [])
    }

    static var configuration: any ApolloAPI.SchemaConfiguration.Type { MockSchemaConfiguration.self }
}

/// Mock schema configuration
internal enum MockSchemaConfiguration: ApolloAPI.SchemaConfiguration {
    static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
        return nil
    }
}

/// Mock root selection set for GraphQL operations
internal struct MockData: RootSelectionSet {
    typealias Schema = MockSchema

    let __data: ApolloAPI.DataDict

    init(_dataDict: ApolloAPI.DataDict) {
        self.__data = _dataDict
    }

    init() {
        self.init(_dataDict: ApolloAPI.DataDict(data: [:], fulfilledFragments: []))
    }

    static var __parentType: any ApolloAPI.ParentType {
        ApolloAPI.Object(typename: "Query", implementedInterfaces: [])
    }
    static var __selections: [ApolloAPI.Selection] { [] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [MockData.self] }
    static var __deferredFragments: [any ApolloAPI.Deferrable.Type] { [] }
    var _fieldData: ApolloAPI.DataDict.FieldValue { __data }
}

// MARK: - Mock GraphQL Operations for Testing

/// Mock query operation for testing GraphQL metadata extraction
internal struct MockQueryOperation: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = "GetUser"
    static let operationType: GraphQLOperationType = .query
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("query GetUser($userId: ID!) { user(id: $userId) { id name } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]?

    init(variables: [String: GraphQLOperationVariableValue]? = nil) {
        self.__variables = variables
    }
}

/// Mock mutation operation for testing GraphQL metadata extraction
internal struct MockMutationOperation: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = "UpdateUser"
    static let operationType: GraphQLOperationType = .mutation
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("mutation UpdateUser($userId: ID!, $name: String!) { updateUser(id: $userId, name: $name) { id name } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]?

    init(variables: [String: GraphQLOperationVariableValue]? = nil) {
        self.__variables = variables
    }
}

/// Mock subscription operation for testing GraphQL metadata extraction
internal struct MockSubscriptionOperation: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = "UserUpdated"
    static let operationType: GraphQLOperationType = .subscription
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("subscription UserUpdated { userUpdated { id name } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]?

    init(variables: [String: GraphQLOperationVariableValue]? = nil) {
        self.__variables = variables
    }
}

/// Mock operation with empty operation name for testing edge cases
internal struct MockEmptyOperation: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = ""
    static let operationType: GraphQLOperationType = .query
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("{ viewer { id } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]?

    init(variables: [String: GraphQLOperationVariableValue]? = nil) {
        self.__variables = variables
    }
}

/// Mock operation with no variables for testing
internal struct MockNoVariablesOperation: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = "GetAllUsers"
    static let operationType: GraphQLOperationType = .query
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("query GetAllUsers { users { id name } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]? = nil
}

// MARK: - Mock GraphQL Enum for Testing

/// Mock enum for testing GraphQLEnum serialization
internal enum MockEnumValue: String, CaseIterable, Sendable, EnumType {
    case optionA = "OPTION_A"
    case optionB = "OPTION_B"
    case optionC = "OPTION_C"

    var _jsonEncodableValue: (any ApolloAPI.JSONEncodable)? {
        return self.rawValue
    }

    var _jsonValue: ApolloAPI.JSONValue {
        return self.rawValue
    }
}

/// Mock operation with GraphQLEnum variables for testing serialization
internal struct MockOperationWithGraphQLEnum: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = "QueryWithEnum"
    static let operationType: GraphQLOperationType = .query
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("query QueryWithEnum($id: ID!, $enumValue: EnumValue!) { item(id: $id, enumValue: $enumValue) { id } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]?

    init(id: String, enumValue: MockEnumValue) {
        self.__variables = [
            "id": id,
            "enumValue": GraphQLEnum(enumValue)
        ]
    }
}

/// Mock operation with GraphQLNullable variables for testing nullable serialization
internal struct MockOperationWithGraphQLNullable: GraphQLOperation {
    typealias Data = MockData

    static let operationName: String = "QueryWithNullable"
    static let operationType: GraphQLOperationType = .query
    static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init("query QueryWithNullable($id: ID!, $optionalName: String) { item(id: $id, optionalName: $optionalName) { id name } }")
    )

    var __variables: [String: GraphQLOperationVariableValue]?

    init(id: String, optionalName: GraphQLNullable<String>) {
        self.__variables = [
            "id": id,
            "optionalName": optionalName
        ]
    }
}

// MARK: - Mock URLSession Components

/// Mock URLSessionDataTask for testing delegate behavior
internal class MockURLSessionDataTask: URLSessionDataTask, @unchecked Sendable {
    private let _response: URLResponse?
    private let _originalRequest: URLRequest?

    init(url: URL, response: URLResponse?) {
        self._response = response
        self._originalRequest = URLRequest(url: url)
        super.init()
    }

    override var response: URLResponse? {
        return _response
    }

    override var originalRequest: URLRequest? {
        return _originalRequest
    }
}
#endif
