/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags
@testable import DatadogInternal

final class FlagsEndpointBuilderTests: XCTestCase {
    func testFlagsEndpointBuilderSupportedSites() throws {
        let testCases: [(DatadogSite, String)] = [
            (.us1, "ff-cdn.datadoghq.com"),
            (.eu1, "ff-cdn.datadoghq.eu"),
            (.us3, "ff-cdn.us3.datadoghq.com"),
            (.us5, "ff-cdn.us5.datadoghq.com"),
            (.ap1, "ff-cdn.ap1.datadoghq.com"),
            (.ap2, "ff-cdn.ap2.datadoghq.com")
        ]

        for (site, expectedHost) in testCases {
            let host = try FlagsEndpointBuilder.buildEndpointHost(site: site)
            XCTAssertEqual(host, expectedHost, "Failed for site: \(site)")

            let url = try FlagsEndpointBuilder.buildEndpointURL(site: site)
            XCTAssertEqual(url, "https://\(expectedHost)/precompute-assignments")
        }
    }

    func testFlagsEndpointBuilderWithCustomerDomain() throws {
        let host = try FlagsEndpointBuilder.buildEndpointHost(site: .us1, customerDomain: "customer123")
        XCTAssertEqual(host, "customer123.ff-cdn.datadoghq.com")

        let url = try FlagsEndpointBuilder.buildEndpointURL(site: .us1, customerDomain: "customer123")
        XCTAssertEqual(url, "https://customer123.ff-cdn.datadoghq.com/precompute-assignments")
    }

    func testFlagsEndpointBuilderWithEmptyCustomerDomain() throws {
        let host = try FlagsEndpointBuilder.buildEndpointHost(site: .us1, customerDomain: "")
        XCTAssertEqual(host, "ff-cdn.datadoghq.com")

        let hostWithNil = try FlagsEndpointBuilder.buildEndpointHost(site: .us1, customerDomain: nil)
        XCTAssertEqual(hostWithNil, "ff-cdn.datadoghq.com")
    }

    func testFlagsEndpointBuilderUnsupportedSites() {
        // Government sites should not be supported for feature flags
        XCTAssertThrowsError(try FlagsEndpointBuilder.buildEndpointHost(site: .us1_fed)) { error in
            if case FlagsError.unsupportedSite(let returnedSite) = error {
                XCTAssertEqual(returnedSite, "us1_fed")
            } else {
                XCTFail("Expected unsupportedSite error, got \(error)")
            }
        }

        XCTAssertThrowsError(try FlagsEndpointBuilder.buildEndpointURL(site: .us1_fed)) { error in
            if case FlagsError.unsupportedSite(let returnedSite) = error {
                XCTAssertEqual(returnedSite, "us1_fed")
            } else {
                XCTFail("Expected unsupportedSite error, got \(error)")
            }
        }
    }

    func testExhaustiveSiteMapping() throws {
        // Test ensures all DatadogSite cases are handled - will fail to compile if new sites are added without updating the switch
        let allSites: [DatadogSite] = [.us1, .us3, .us5, .eu1, .ap1, .ap2, .us1_fed]

        for site in allSites {
            if site == .us1_fed {
                // Should throw for unsupported government site
                XCTAssertThrowsError(try FlagsEndpointBuilder.buildEndpointHost(site: site))
            } else {
                // Should succeed for all other sites
                XCTAssertNoThrow(try FlagsEndpointBuilder.buildEndpointHost(site: site))
            }
        }
    }

    func testExtractCustomerDomainPlaceholder() {
        // This tests the current placeholder implementation
        let domain = FlagsEndpointBuilder.extractCustomerDomain(from: "any-client-token")
        XCTAssertNil(domain)
    }
}
