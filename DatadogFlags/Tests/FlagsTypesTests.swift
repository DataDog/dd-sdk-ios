/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags

final class FlagsTypesTests: XCTestCase {
    
    func testFlagsEvaluationContext() {
        let context = FlagsEvaluationContext(
            targetingKey: "user-123",
            attributes: [
                "email": "user@example.com",
                "product": "premium",
                "region": "us-east-1"
            ]
        )
        
        XCTAssertEqual(context.targetingKey, "user-123")
        XCTAssertEqual(context.attributes["email"] as? String, "user@example.com")
        XCTAssertEqual(context.attributes["product"] as? String, "premium")
        XCTAssertEqual(context.attributes["region"] as? String, "us-east-1")
    }
    
    func testFlagsEvaluationContextWithEmptyAttributes() {
        let context = FlagsEvaluationContext(targetingKey: "user-456")
        
        XCTAssertEqual(context.targetingKey, "user-456")
        XCTAssertTrue(context.attributes.isEmpty)
    }
    
    func testFlagsMetadata() {
        let context = FlagsEvaluationContext(targetingKey: "test-user", attributes: ["key": "value"])
        let timestamp: Double = 1234567890123.0
        
        let metadata = FlagsMetadata(fetchedAt: timestamp, context: context)
        
        XCTAssertEqual(metadata.fetchedAt, timestamp)
        XCTAssertEqual(metadata.context?.targetingKey, "test-user")
        XCTAssertEqual(metadata.context?.attributes["key"] as? String, "value")
    }
    
    func testFlagsMetadataWithoutContext() {
        let timestamp: Double = 1234567890123.0
        
        let metadata = FlagsMetadata(fetchedAt: timestamp, context: nil)
        
        XCTAssertEqual(metadata.fetchedAt, timestamp)
        XCTAssertNil(metadata.context)
    }
}
