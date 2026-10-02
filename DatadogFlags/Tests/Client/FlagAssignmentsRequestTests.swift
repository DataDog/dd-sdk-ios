/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FlagAssignmentsRequestTests: XCTestCase {
    private let testURL = URL(string: "https://test.example.com/precompute-assignments")!

    func testWrapperRequestReportsLoadedJavaScriptVersion() throws {
        let request = try URLRequest.flagAssignmentsRequest(
            url: testURL,
            evaluationContext: .init(targetingKey: "athlete", attributes: ["sdk_version": .string("99.99.99")]),
            context: .mockWith(source: "react-native", sdkVersion: "88.88.88"),
            customHeaders: nil,
            wrapperSource: FlagsWrapperSource(
                sdkName: "dd-sdk-reactnative", sdkVersion: "4.2.0-js.1"
            )
        )
        let source = try requestSource(request)
        XCTAssertEqual(source["sdk_name"] as? String, "dd-sdk-reactnative")
        XCTAssertEqual(source["sdk_version"] as? String, "4.2.0-js.1")
        XCTAssertEqual(source.count, 2)
    }

    func testLegacyWrapperDoesNotClaimNativeOnlySupport() throws {
        let request = try URLRequest.flagAssignmentsRequest(
            url: testURL,
            evaluationContext: .init(targetingKey: "athlete", attributes: [:]),
            context: .mockWith(source: "react-native", sdkVersion: "88.88.88"),
            customHeaders: nil
        )
        let source = try requestSource(request)
        XCTAssertEqual(source["sdk_name"] as? String, "dd-sdk-reactnative")
        XCTAssertEqual(source["sdk_version"] as? String, "unknown")
        XCTAssertEqual(source.count, 2)
    }

    private func requestSource(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let data = try XCTUnwrap(body["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        return try XCTUnwrap(attributes["source"] as? [String: Any])
    }

    func testFlagAssignmentsRequest() throws {
        // Given
        let evaluationContext = FlagsEvaluationContext(
            targetingKey: "user123",
            attributes: [
                "plan": .string("premium"),
                "userId": .string("123")
            ]
        )
        let context = DatadogContext.mockWith(
            clientToken: "test-token",
            env: "production",
            sdkVersion: "3.5.1",
            additionalContext: [RUMCoreContext.mockWith(applicationID: "test-app-id")]
        )
        let customHeaders = ["X-Custom-Header": "custom-value"]
        let expectedBody = """
        {
          "data" : {
            "attributes" : {
              "env" : {
                "dd_env" : "production",
                "name" : "production"
              },
              "source" : {
                "sdk_name" : "dd-sdk-ios",
                "sdk_version" : "\(FlagsSDKMetadata.version)"
              },
              "subject" : {
                "targeting_attributes" : {
                  "plan" : "premium",
                  "userId" : "123"
                },
                "targeting_key" : "user123"
              }
            },
            "type" : "precompute-assignments-request"
          }
        }
        """

        // When
        let request = try URLRequest.flagAssignmentsRequest(
            url: testURL,
            evaluationContext: evaluationContext,
            context: context,
            customHeaders: customHeaders
        )

        // Then
        XCTAssertEqual(request.url, testURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/vnd.api+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "gzip, deflate, br")
        XCTAssertEqual(request.value(forHTTPHeaderField: "dd-client-token"), "test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "dd-application-id"), "test-app-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
        let actualBody = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(actualBody.normalizedJSON, expectedBody.normalizedJSON)
    }
}

// MARK: - Test Helpers

extension String {
    fileprivate var normalizedJSON: String {
        // Normalizes JSON string by parsing and re-serializing with sorted keys and pretty printing.
        // This allows for comparing JSON content regardless of formatting or key ordering.
        guard let data = self.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let normalized = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]),
              let result = String(data: normalized, encoding: .utf8) else {
            return self
        }
        return result
    }
}
