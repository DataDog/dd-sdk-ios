/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags

final class FlagsEndpointBuilderTests: XCTestCase {
    
    func testFlagsEndpointBuilderSupportedSites() throws {
        let testCases = [
            ("datadoghq.com", "ff-cdn.datadoghq.com"),
            ("datadoghq.eu", "ff-cdn.datadoghq.eu"),
            ("us3.datadoghq.com", "ff-cdn.us3.datadoghq.com"),
            ("us5.datadoghq.com", "ff-cdn.us5.datadoghq.com"),
            ("ap1.datadoghq.com", "ff-cdn.ap1.datadoghq.com"),
            ("ap2.datadoghq.com", "ff-cdn.ap2.datadoghq.com"),
            ("datad0g.com", "ff-cdn.datad0g.com")
        ]
        
        for (site, expectedHost) in testCases {
            let host = try FlagsEndpointBuilder.buildEndpointHost(site: site)
            XCTAssertEqual(host, expectedHost, "Failed for site: \(site)")
            
            let url = try FlagsEndpointBuilder.buildEndpointURL(site: site)
            XCTAssertEqual(url, "https://\(expectedHost)/precompute-assignments")
        }
    }
    
    func testFlagsEndpointBuilderWithCustomerDomain() throws {
        let host = try FlagsEndpointBuilder.buildEndpointHost(site: "datadoghq.com", customerDomain: "customer123")
        XCTAssertEqual(host, "customer123.ff-cdn.datadoghq.com")
        
        let url = try FlagsEndpointBuilder.buildEndpointURL(site: "datadoghq.com", customerDomain: "customer123")
        XCTAssertEqual(url, "https://customer123.ff-cdn.datadoghq.com/precompute-assignments")
    }
    
    func testFlagsEndpointBuilderWithEmptyCustomerDomain() throws {
        let host = try FlagsEndpointBuilder.buildEndpointHost(site: "datadoghq.com", customerDomain: "")
        XCTAssertEqual(host, "ff-cdn.datadoghq.com")
        
        let hostWithNil = try FlagsEndpointBuilder.buildEndpointHost(site: "datadoghq.com", customerDomain: nil)
        XCTAssertEqual(hostWithNil, "ff-cdn.datadoghq.com")
    }
    
    func testFlagsEndpointBuilderUnsupportedSites() {
        let unsupportedSites = ["ddog-gov.com", "invalid.site.com", ""]
        
        for site in unsupportedSites {
            XCTAssertThrowsError(try FlagsEndpointBuilder.buildEndpointHost(site: site)) { error in
                if case FlagsError.unsupportedSite(let returnedSite) = error {
                    XCTAssertEqual(returnedSite.lowercased(), site.lowercased())
                } else {
                    XCTFail("Expected unsupportedSite error, got \(error)")
                }
            }
        }
    }
    
    func testFlagsEndpointBuilderCaseInsensitive() throws {
        let host1 = try FlagsEndpointBuilder.buildEndpointHost(site: "DATADOGHQ.COM")
        let host2 = try FlagsEndpointBuilder.buildEndpointHost(site: "datadoghq.com")
        
        XCTAssertEqual(host1, host2)
        XCTAssertEqual(host1, "ff-cdn.datadoghq.com")
    }
    
    func testExtractCustomerDomainPlaceholder() {
        // This tests the current placeholder implementation
        let domain = FlagsEndpointBuilder.extractCustomerDomain(from: "any-client-token")
        XCTAssertNil(domain)
    }
}
