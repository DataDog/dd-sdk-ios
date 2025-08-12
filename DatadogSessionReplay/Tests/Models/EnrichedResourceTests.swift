/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
@testable import DatadogSessionReplay

final class EnrichedResourceTests: XCTestCase {
    func testDecodingWithMimeType() throws {
        let json = """
        {
            "identifier": "test-resource-123",
            "data": "aGVsbG8gd29ybGQ=",
            "mimeType": "image/svg+xml",
            "context": {
                "type": "resource",
                "application": {
                    "id": "test-app-123"
                }
            }
        }
        """.data(using: .utf8)!

        let resource = try JSONDecoder().decode(EnrichedResource.self, from: json)

        XCTAssertEqual(resource.identifier, "test-resource-123")
        XCTAssertEqual(resource.data, Data(base64Encoded: "aGVsbG8gd29ybGQ=")!)
        XCTAssertEqual(resource.mimeType, "image/svg+xml")
        XCTAssertEqual(resource.context.type, "resource")
        XCTAssertEqual(resource.context.application.id, "test-app-123")
    }

    func testDecodingWithoutMimeTypeUsesDefaultPNG() throws {
        let json = """
        {
            "identifier": "legacy-resource-456",
            "data": "aW1hZ2VieXRlcw==",
            "context": {
                "type": "resource",
                "application": {
                    "id": "test-app-123"
                }
            }
        }
        """.data(using: .utf8)!

        let resource = try JSONDecoder().decode(EnrichedResource.self, from: json)

        XCTAssertEqual(resource.identifier, "legacy-resource-456")
        XCTAssertEqual(resource.data, Data(base64Encoded: "aW1hZ2VieXRlcw==")!)
        XCTAssertEqual(resource.mimeType, "image/png", "Should default to PNG for backward compatibility")
        XCTAssertEqual(resource.context.type, "resource")
        XCTAssertEqual(resource.context.application.id, "test-app-123")
    }
}

#endif
