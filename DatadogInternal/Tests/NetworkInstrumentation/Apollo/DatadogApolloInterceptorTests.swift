/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import XCTest
@preconcurrency import ApolloAPI
import Apollo
@testable import DatadogInternal

public final class DatadogApolloInterceptorTests: XCTestCase {
    func testInterceptorForwardsMetadataWithoutPayloadByDefault() async throws {
        let request = JSONRequest(
            operation: MockQueryOperation(variables: ["userId": "123"]),
            graphQLEndpoint: URL(string: "https://example.com/graphql")!,
            fetchBehavior: .NetworkOnly,
            writeResultsToCache: false,
            requestTimeout: nil
        )
        let forwarded = expectation(description: "Request forwarded")

        _ = try await DatadogApolloInterceptor().intercept(request: request) { modifiedRequest in
            XCTAssertEqual(modifiedRequest.additionalHeaders[GraphQLHeaders.operationName], "GetUser")
            XCTAssertEqual(modifiedRequest.additionalHeaders[GraphQLHeaders.operationType], "query")
            XCTAssertEqual(modifiedRequest.additionalHeaders[GraphQLHeaders.variables], "{\"userId\":\"123\"}")
            XCTAssertNil(modifiedRequest.additionalHeaders[GraphQLHeaders.payload])
            XCTAssertEqual(modifiedRequest.additionalHeaders["Content-Type"], "application/json")
            forwarded.fulfill()
            return .init(stream: AsyncThrowingStream { $0.finish() })
        }

        await fulfillment(of: [forwarded], timeout: 1)
        XCTAssertNil(request.additionalHeaders[GraphQLHeaders.operationName])
    }

    func testInterceptorIncludesPayloadOnlyWhenEnabled() async throws {
        let request = JSONRequest(
            operation: MockQueryOperation(),
            graphQLEndpoint: URL(string: "https://example.com/graphql")!,
            fetchBehavior: .NetworkOnly,
            writeResultsToCache: false,
            requestTimeout: nil
        )
        let forwarded = expectation(description: "Request forwarded")

        _ = try await DatadogApolloInterceptor(sendGraphQLPayloads: true).intercept(request: request) { modifiedRequest in
            XCTAssertEqual(
                modifiedRequest.additionalHeaders[GraphQLHeaders.payload],
                "query GetUser($userId: ID!) { user(id: $userId) { id name } }"
            )
            XCTAssertNil(modifiedRequest.additionalHeaders[GraphQLHeaders.variables])
            forwarded.fulfill()
            return .init(stream: AsyncThrowingStream { $0.finish() })
        }

        await fulfillment(of: [forwarded], timeout: 1)
    }

    // MARK: - Header Constants Tests

    func testGraphQLHeadersConstants() throws {
        // Verify header constants match Android implementation
        XCTAssertEqual(GraphQLHeaders.operationName, "_dd-custom-header-graph-ql-operation-name")
        XCTAssertEqual(GraphQLHeaders.operationType, "_dd-custom-header-graph-ql-operation-type")
        XCTAssertEqual(GraphQLHeaders.variables, "_dd-custom-header-graph-ql-variables")
        XCTAssertEqual(GraphQLHeaders.payload, "_dd-custom-header-graph-ql-payload")
    }

    // MARK: - GraphQL Operation Tests

    func testExtractPayloadWithEmptyOperationName() throws {
        let extractor = GraphQLMetadataExtractor()
        let operation = MockEmptyOperation()
        let result = extractor.extractPayload(from: operation)
        XCTAssertNotNil(result) // Should still create an empty JSON payload

        // Should have empty operationName but still be valid JSON
        guard let payload = result else {
            XCTFail("Expected non-nil payload")
            return
        }
        XCTAssertFalse(payload.contains("operationName"))
        XCTAssertFalse(payload.contains("variables"))
    }

    func testExtractVariablesFromQueryOperation() throws {
        let extractor = GraphQLMetadataExtractor()
        let variables: [String: GraphQLOperationVariableValue] = ["userId": "123", "active": true]
        let operation = MockQueryOperation(variables: variables)

        let result = extractor.extractVariables(from: operation)
        XCTAssertNotNil(result)
        guard let variables = result else {
            XCTFail("Expected non-nil variables")
            return
        }
        XCTAssertTrue(variables.contains("userId"))
        XCTAssertTrue(variables.contains("123"))
        XCTAssertTrue(variables.contains("active"))
    }

    func testExtractVariablesFromOperationWithNoVariables() throws {
        let extractor = GraphQLMetadataExtractor()
        let operation = MockNoVariablesOperation()

        let result = extractor.extractVariables(from: operation)
        XCTAssertNil(result) // Should return nil for empty variables
    }

    func testExtractOperationTypeFromOperations() throws {
        let extractor = GraphQLMetadataExtractor()
        let operation1 = MockQueryOperation()
        let operation2 = MockMutationOperation()
        let operation3 = MockSubscriptionOperation()

        let result1 = extractor.extractOperationType(from: operation1)
        let result2 = extractor.extractOperationType(from: operation2)
        let result3 = extractor.extractOperationType(from: operation3)

        XCTAssertEqual(result1, "query")
        XCTAssertEqual(result2, "mutation")
        XCTAssertEqual(result3, "subscription")
    }

    func testExtractPayloadContainsQueryDocument() throws {
        let extractor = GraphQLMetadataExtractor()
        let operation = MockQueryOperation(variables: ["userId": "123"])

        let result = extractor.extractPayload(from: operation)
        XCTAssertNotNil(result)

        guard let payload = result else {
            XCTFail("Expected non-nil payload")
            return
        }

        // Payload should contain the GraphQL query document
        XCTAssertTrue(payload.contains("query GetUser"))
        XCTAssertTrue(payload.contains("user(id: $userId)"))
    }

    // MARK: - GraphQL Variables Tests

    func testExtractVariablesWithGraphQLEnum() throws {
        // Test that GraphQLEnum types are properly serialized to JSON
        let extractor = GraphQLMetadataExtractor()
        let operation = MockOperationWithGraphQLEnum(id: "test-123", enumValue: .optionB)

        let result = extractor.extractVariables(from: operation)

        XCTAssertNotNil(result)
        guard let variables = result else {
            XCTFail("Expected non-nil variables")
            return
        }

        // Verify the enum is serialized as its string value
        XCTAssertTrue(variables.contains("OPTION_B"))
        XCTAssertTrue(variables.contains("test-123"))
    }

    func testExtractVariablesWithNonASCIICharacters() throws {
        // Test that non-ASCII characters are properly handled in variables
        let extractor = GraphQLMetadataExtractor()
        let variables: [String: GraphQLOperationVariableValue] = [
            "userId": "user-123",
            "name": "José García",
            "city": "São Paulo",
            "description": "Test with émojis 🎉 and spëcial çhars"
        ]
        let operation = MockQueryOperation(variables: variables)

        let result = extractor.extractVariables(from: operation)

        XCTAssertNotNil(result)
        guard let variablesJson = result else {
            XCTFail("Expected non-nil variables")
            return
        }

        // Verify non-ASCII characters are preserved in the JSON output
        XCTAssertTrue(variablesJson.contains("José García"))
        XCTAssertTrue(variablesJson.contains("São Paulo"))
        XCTAssertTrue(variablesJson.contains("🎉"))
        XCTAssertTrue(variablesJson.contains("émojis"))
        XCTAssertTrue(variablesJson.contains("spëcial"))
        XCTAssertTrue(variablesJson.contains("çhars"))
    }

    func testExtractVariablesWithGraphQLNullableNone() throws {
        // Preserve the standalone integration's handling of GraphQLNullable<String>.none.
        let extractor = GraphQLMetadataExtractor()
        let operation = MockOperationWithGraphQLNullable(id: "item-456", optionalName: .none)

        let result = extractor.extractVariables(from: operation)

        XCTAssertNotNil(result)
        guard let variablesJson = result else {
            XCTFail("Expected non-nil variables")
            return
        }

        // Verify the ID is present
        XCTAssertTrue(variablesJson.contains("item-456"))
        XCTAssertTrue(variablesJson.contains("optionalName"))

        // Verify the nullable .none value is serialized as a string representation
        XCTAssertTrue(variablesJson.contains("none"), "Expected 'none' in JSON output but got: \(variablesJson)")

        // Additionally verify it's valid JSON that can be parsed back
        guard
            let jsonData = variablesJson.data(using: .utf8),
            let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as?
            [String: Any]
        else {
            XCTFail("Expected valid JSON output")
            return
        }

        // Verify the parsed JSON has the expected structure
        XCTAssertEqual(parsedJson["id"] as? String, "item-456")
        XCTAssertTrue(parsedJson.keys.contains("optionalName"))
        // The value should be a string representation of the GraphQLNullable
        XCTAssertTrue(parsedJson["optionalName"] is String, "Expected String for optionalName but got: \(String(describing: parsedJson["optionalName"]))")
        XCTAssertTrue((parsedJson["optionalName"] as? String)?.contains("none") == true, "Expected string to contain 'none'")
    }
}
#endif
