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
    func testCreate() {
        // Given
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let defaultClient = FlagsClient.create(in: core)
        let nopDefaultClient = FlagsClient.create(in: core)
        let namedClient = FlagsClient.create(name: "test", in: core)
        let nopNamedClient = FlagsClient.create(name: "test", in: core)

        // Then
        XCTAssertTrue(defaultClient is FlagsClient)
        XCTAssertTrue(nopDefaultClient is NOPFlagsClient)
        XCTAssertTrue(namedClient is FlagsClient)
        XCTAssertTrue(nopNamedClient is NOPFlagsClient)
    }

    func testCreateWhenFlagsNotEnabled() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()

        // When
        let client = FlagsClient.create(in: core)

        // Then
        XCTAssertTrue(client is NOPFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Flags feature must be enabled before calling `FlagsClient.create(name:with:in:)`."
        )
    }

    func testInstance() {
        // Given
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let createdClient = FlagsClient.create(in: core)
        let client = FlagsClient.instance(in: core)
        let createdNamedClient = FlagsClient.create(name: "test", in: core)
        let namedClient = FlagsClient.instance(named: "test", in: core)
        let notFoundClient = FlagsClient.instance(named: "foo", in: core)

        // Then
        XCTAssertIdentical(client, createdClient)
        XCTAssertIdentical(namedClient, createdNamedClient)
        XCTAssertTrue(notFoundClient is NOPFlagsClient)
    }

    func testInstanceWhenFlagsNotEnabled() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()

        // When
        let client = FlagsClient.instance(in: core)

        // Then
        XCTAssertTrue(client is NOPFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Flags feature must be enabled before calling `FlagsClient.instance(named:in:)`."
        )
    }

    func testFlagsClientWithMockHttpClient() {
        // Given
        let expectation = expectation(description: "Flags loaded")

        let mockHttpClient = MockFlagsHTTPClient()
        let repositoryMock = FlagsRepositoryMock()
        let config = FlagsClient.Configuration()
        let exposureLoggerMock = ExposureLoggerMock()
        let client = FlagsClient(
            configuration: config,
            httpClient: mockHttpClient,
            repository: repositoryMock,
            exposureLogger: exposureLoggerMock,
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock()
        )

        let context = FlagsEvaluationContext(
            targetingKey: "test_subject",
            attributes: ["attr1": "value1", "companyId": "1"]
        )

        // When
        client.setEvaluationContext(context) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
        }

        waitForExpectations(timeout: 1.0)

        let boolValue = client.getBooleanValue(key: "boolean-flag", defaultValue: false)
        let stringValue = client.getStringValue(key: "string-flag", defaultValue: "default")
        let integerValue = client.getIntegerValue(key: "integer-flag", defaultValue: 0)
        let doubleValue = client.getDoubleValue(key: "numeric-flag", defaultValue: 0.0)
        let objectValue = client.getObjectValue(key: "json-flag", defaultValue: .null)

        let boolDetails = client.getBooleanDetails(key: "boolean-flag", defaultValue: false)
        let flagNotFoundDetails = client.getBooleanDetails(key: "missing-flag", defaultValue: false)
        let typeMismatchDetails = client.getBooleanDetails(key: "string-flag", defaultValue: false)

        // Then
        XCTAssertTrue(boolValue)
        XCTAssertEqual(stringValue, "red")
        XCTAssertEqual(integerValue, 42)
        XCTAssertEqual(doubleValue, 3.14, accuracy: 0.001)
        XCTAssertEqual(
            objectValue,
            .dictionary(
                [
                    "key": .string("value"),
                    "prop": .int(123)
                ]
            )
        )
        XCTAssertEqual(exposureLoggerMock.logExposureCalls.count, 6)

        XCTAssertEqual(
            boolDetails,
            FlagDetails(
                key: "boolean-flag",
                value: true,
                variant: "variation-124",
                reason: "TARGETING_MATCH"
            )
        )
        XCTAssertEqual(
            flagNotFoundDetails,
            .init(
                key: "missing-flag",
                value: false,
                error: .flagNotFound
            )
        )
        XCTAssertEqual(
            typeMismatchDetails,
            .init(
                key: "string-flag",
                value: false,
                error: .typeMismatch
            )
        )
    }

    func testContextAttributeSerialization() {
        let expectation = expectation(description: "Context serialization test")

        let config = FlagsClient.Configuration()
        let client = FlagsClient(
            configuration: config,
            httpClient: AttributeSerializationTestClient(),
            repository: FlagsRepositoryMock(),
            exposureLogger: ExposureLoggerMock(),
            dateProvider: DateProviderMock(),
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
