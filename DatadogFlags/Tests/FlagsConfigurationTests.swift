/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags

final class FlagsConfigurationTests: XCTestCase {
    
    func testFlagsClientConfiguration() {
        let config = FlagsClientConfiguration(
            clientToken: "test-token",
            environment: "staging",
            baseURL: "https://custom.example.com"
        )
        
        XCTAssertEqual(config.clientToken, "test-token")
        XCTAssertEqual(config.environment, "staging")
        XCTAssertEqual(config.baseURL, "https://custom.example.com")
    }
    
    func testFlagsClientConfigurationDefaults() {
        let config = FlagsClientConfiguration(clientToken: "test-token")
        
        XCTAssertEqual(config.clientToken, "test-token")
        XCTAssertEqual(config.environment, "prod")
        XCTAssertNil(config.baseURL)
        XCTAssertEqual(config.site, "datadoghq.com")
        XCTAssertNil(config.applicationId)
        XCTAssertTrue(config.customHeaders.isEmpty)
        XCTAssertNil(config.flaggingProxy)
    }
    
    func testFlagsClientConfigurationWithAllParameters() {
        let customHeaders = ["X-Custom": "value", "X-Test": "test"]
        let config = FlagsClientConfiguration(
            clientToken: "test-token",
            environment: "staging", 
            baseURL: "https://custom.example.com",
            site: "datadoghq.eu",
            applicationId: "app-123",
            customHeaders: customHeaders,
            flaggingProxy: "proxy.example.com"
        )
        
        XCTAssertEqual(config.clientToken, "test-token")
        XCTAssertEqual(config.environment, "staging")
        XCTAssertEqual(config.baseURL, "https://custom.example.com")
        XCTAssertEqual(config.site, "datadoghq.eu")
        XCTAssertEqual(config.applicationId, "app-123")
        XCTAssertEqual(config.customHeaders, customHeaders)
        XCTAssertEqual(config.flaggingProxy, "proxy.example.com")
    }
}
