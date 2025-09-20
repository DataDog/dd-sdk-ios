/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogFlags

final class FlagsClientTests: XCTestCase {
    func testFlagsClientCreation() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        let config = FlagsClient.Configuration()
        let client = FlagsClient.create(with: config, in: core)

        XCTAssertNotNil(client) // TODO: FFL-1016 Assert that it is not a NOPFlagsClient
    }

    func testFlagsClientWithMockHttpClient() {
        let expectation = expectation(description: "Flags loaded")

        let mockHttpClient = MockFlagsHTTPClient()
        let mockStore = MockFlagsStore()
        let config = FlagsClient.Configuration()
        let client = FlagsClient(
            configuration: config,
            httpClient: mockHttpClient,
            store: mockStore,
            featureScope: FeatureScopeMock()
        )

        let context = FlagsEvaluationContext(
            targetingKey: "test_subject",
            attributes: ["attr1": "value1", "companyId": "1"]
        )

        client.setEvaluationContext(context) { result in
            switch result {
            case .success:
                let boolValue = client.getBooleanValue(key: "boolean-flag", defaultValue: false)
                let stringValue = client.getStringValue(key: "string-flag", defaultValue: "default")
                let integerValue = client.getIntegerValue(key: "integer-flag", defaultValue: 0)
                let doubleValue = client.getDoubleValue(key: "numeric-flag", defaultValue: 0.0)
                let objectValue = client.getObjectValue(key: "json-flag", defaultValue: [:])

                XCTAssertTrue(boolValue)
                XCTAssertEqual(stringValue, "red")
                XCTAssertEqual(integerValue, 42)
                XCTAssertEqual(doubleValue, 3.14, accuracy: 0.001)
                XCTAssertEqual(objectValue["key"] as? String, "value")
                XCTAssertEqual(objectValue["prop"] as? Int, 123)

                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
        }

        waitForExpectations(timeout: 1.0)
    }

    func testContextAttributeSerialization() {
        let expectation = expectation(description: "Context serialization test")

        let config = FlagsClient.Configuration()
        let client = FlagsClient(
            configuration: config,
            httpClient: AttributeSerializationTestClient(),
            store: MockFlagsStore(),
            featureScope: FeatureScopeMock()
        )

        let stringAttributes: [String: String] = [
            "stringValue": "test",
            "intValue": "42",
            "boolValue": "true",
            "arrayValue": "[\"a\", \"b\", \"c\"]",
            "dictValue": "{\"key\": \"value\", \"number\": \"123\"}"
        ]

        let context = FlagsEvaluationContext(
            targetingKey: "test-user",
            attributes: stringAttributes
        )

        client.setEvaluationContext(context) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
        }

        waitForExpectations(timeout: 1.0)
    }
}

// MARK: - Test Helpers

private class MockFlagsHTTPClient: FlagsHTTPClient {
    func postPrecomputeAssignments(
        context: FlagsEvaluationContext,
        configuration: FlagsClient.Configuration,
        sdkContext: DatadogContext,
        completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
    ) {
        // Try to load from bundle resource
        let testBundle = Bundle(for: FlagsClientTests.self)
        guard let url = testBundle.url(forResource: "precomputed-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            completion(.failure(FlagsError.invalidResponse))
            return
        }

        let response = HTTPURLResponse(
            url: URL(string: "https://test.example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        completion(.success((data, response)))
    }
}

private class MockFlagsStore: FlagsStore {
    private var flags: [String: Any] = [:]

    init() {
        super.init(featureScope: FeatureScopeMock())
    }

    override func getFlags() -> [String: Any] {
        return flags
    }

    override func setFlags(_ flags: [String: Any]) {
        self.flags = flags
    }

    override func setFlags(_ flags: [String: Any], context: FlagsEvaluationContext?) {
        self.flags = flags
    }
}

private class AttributeSerializationTestClient: FlagsHTTPClient {
    func postPrecomputeAssignments(
        context: FlagsEvaluationContext,
        configuration: FlagsClient.Configuration,
        sdkContext: DatadogContext,
        completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
    ) {
        // Verify that the context attributes are properly typed as [String: String]
        let attributes = context.attributes

        // Verify attributes are correctly passed as strings
        XCTAssertEqual(attributes["stringValue"], "test")
        XCTAssertEqual(attributes["intValue"], "42")
        XCTAssertEqual(attributes["boolValue"], "true")
        XCTAssertEqual(attributes["arrayValue"], "[\"a\", \"b\", \"c\"]")
        XCTAssertEqual(attributes["dictValue"], "{\"key\": \"value\", \"number\": \"123\"}")

        // Return success with empty flags
        let responseData: [String: Any] = [
            "data": [
                "type": "precomputed-assignments",
                "attributes": [
                    "flags": [:]
                ]
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: responseData)
            let response = HTTPURLResponse(
                url: URL(string: "https://test.example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            completion(.success((data, response)))
        } catch {
            completion(.failure(error))
        }
    }
}
