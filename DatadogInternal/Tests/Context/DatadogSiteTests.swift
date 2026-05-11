/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

class DatadogSiteTests: XCTestCase {
    // MARK: - remoteConfigurationURL per site

    func testUS1RemoteConfigurationURL() {
        let url = DatadogSite.us1.remoteConfigurationURL(for: "abc-123")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/abc-123.json")
    }

    func testUS3RemoteConfigurationURL() {
        let expected = "https://sdk-configuration.browser-intake-us3-datadoghq.com/v1/abc-123.json"
        XCTAssertEqual(DatadogSite.us3.remoteConfigurationURL(for: "abc-123")?.absoluteString, expected)
    }

    func testUS5RemoteConfigurationURL() {
        let expected = "https://sdk-configuration.browser-intake-us5-datadoghq.com/v1/abc-123.json"
        XCTAssertEqual(DatadogSite.us5.remoteConfigurationURL(for: "abc-123")?.absoluteString, expected)
    }

    func testEU1RemoteConfigurationURL() {
        let url = DatadogSite.eu1.remoteConfigurationURL(for: "abc-123")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.eu/v1/abc-123.json")
    }

    func testAP1RemoteConfigurationURL() {
        let expected = "https://sdk-configuration.browser-intake-ap1-datadoghq.com/v1/abc-123.json"
        XCTAssertEqual(DatadogSite.ap1.remoteConfigurationURL(for: "abc-123")?.absoluteString, expected)
    }

    func testAP2RemoteConfigurationURL() {
        let expected = "https://sdk-configuration.browser-intake-ap2-datadoghq.com/v1/abc-123.json"
        XCTAssertEqual(DatadogSite.ap2.remoteConfigurationURL(for: "abc-123")?.absoluteString, expected)
    }

    func testUS1FedRemoteConfigurationURL() {
        let url = DatadogSite.us1_fed.remoteConfigurationURL(for: "abc-123")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-ddog-gov.com/v1/abc-123.json")
    }

    func testUS2FedRemoteConfigurationURL() {
        let expected = "https://sdk-configuration.browser-intake-us2-ddog-gov.com/v1/abc-123.json"
        XCTAssertEqual(DatadogSite.us2_fed.remoteConfigurationURL(for: "abc-123")?.absoluteString, expected)
    }

    // MARK: - ID encoding

    func testIDWithSpacesIsPercentEncoded() {
        let url = DatadogSite.us1.remoteConfigurationURL(for: "hello world")
        let expected = "https://sdk-configuration.browser-intake-datadoghq.com/v1/hello%20world.json"
        XCTAssertNotNil(url, "URL must be constructed even when id contains spaces")
        XCTAssertEqual(url?.absoluteString, expected)
    }

    func testIDWithSlashDoesNotProduceExtraPathSegments() {
        // A slash in the ID must be encoded as %2F, not left as a literal path separator.
        // Without this, "a/b" would produce …/v1/a/b.json (wrong path) instead of …/v1/a%2Fb.json.
        let url = DatadogSite.us1.remoteConfigurationURL(for: "a/b")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/a%2Fb.json")
    }
}
