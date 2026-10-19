/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

class DatadogSiteTests: XCTestCase {
    // MARK: - host per site

    func testUS1Host() { XCTAssertEqual(DatadogSite.us1.host, "browser-intake-datadoghq.com") }
    func testUS3Host() { XCTAssertEqual(DatadogSite.us3.host, "browser-intake-us3-datadoghq.com") }
    func testUS5Host() { XCTAssertEqual(DatadogSite.us5.host, "browser-intake-us5-datadoghq.com") }
    func testEU1Host() { XCTAssertEqual(DatadogSite.eu1.host, "browser-intake-datadoghq.eu") }
    func testAP1Host() { XCTAssertEqual(DatadogSite.ap1.host, "browser-intake-ap1-datadoghq.com") }
    func testAP2Host() { XCTAssertEqual(DatadogSite.ap2.host, "browser-intake-ap2-datadoghq.com") }
    func testUS1FedHost() { XCTAssertEqual(DatadogSite.us1_fed.host, "browser-intake-ddog-gov.com") }
    func testUS2FedHost() { XCTAssertEqual(DatadogSite.us2_fed.host, "browser-intake-us2-ddog-gov.com") }

    // MARK: - endpoint per site

    func testUS1Endpoint() { XCTAssertEqual(DatadogSite.us1.endpoint.absoluteString, "https://browser-intake-datadoghq.com/") }
    func testUS3Endpoint() { XCTAssertEqual(DatadogSite.us3.endpoint.absoluteString, "https://browser-intake-us3-datadoghq.com/") }
    func testUS5Endpoint() { XCTAssertEqual(DatadogSite.us5.endpoint.absoluteString, "https://browser-intake-us5-datadoghq.com/") }
    func testEU1Endpoint() { XCTAssertEqual(DatadogSite.eu1.endpoint.absoluteString, "https://browser-intake-datadoghq.eu/") }
    func testAP1Endpoint() { XCTAssertEqual(DatadogSite.ap1.endpoint.absoluteString, "https://browser-intake-ap1-datadoghq.com/") }
    func testAP2Endpoint() { XCTAssertEqual(DatadogSite.ap2.endpoint.absoluteString, "https://browser-intake-ap2-datadoghq.com/") }
    func testUS1FedEndpoint() { XCTAssertEqual(DatadogSite.us1_fed.endpoint.absoluteString, "https://browser-intake-ddog-gov.com/") }
    func testUS2FedEndpoint() { XCTAssertEqual(DatadogSite.us2_fed.endpoint.absoluteString, "https://browser-intake-us2-ddog-gov.com/") }

    // MARK: - remoteConfigurationEndpoint per site

    func testUS1RemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.us1.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/")
    }

    func testUS3RemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.us3.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-us3-datadoghq.com/")
    }

    func testUS5RemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.us5.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-us5-datadoghq.com/")
    }

    func testEU1RemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.eu1.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.eu/")
    }

    func testAP1RemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.ap1.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-ap1-datadoghq.com/")
    }

    func testAP2RemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.ap2.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-ap2-datadoghq.com/")
    }

    func testUS1FedRemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.us1_fed.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-ddog-gov.com/")
    }

    func testUS2FedRemoteConfigurationEndpoint() {
        XCTAssertEqual(DatadogSite.us2_fed.remoteConfigurationEndpoint.absoluteString, "https://sdk-configuration.browser-intake-us2-ddog-gov.com/")
    }
}
