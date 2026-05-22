/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
import DatadogInternal

class DatadogSiteTests: XCTestCase {
    // MARK: - remoteConfigurationHost per site

    func testUS1RemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.us1.remoteConfigurationHost, "sdk-configuration.browser-intake-datadoghq.com")
    }

    func testUS3RemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.us3.remoteConfigurationHost, "sdk-configuration.browser-intake-us3-datadoghq.com")
    }

    func testUS5RemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.us5.remoteConfigurationHost, "sdk-configuration.browser-intake-us5-datadoghq.com")
    }

    func testEU1RemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.eu1.remoteConfigurationHost, "sdk-configuration.browser-intake-datadoghq.eu")
    }

    func testAP1RemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.ap1.remoteConfigurationHost, "sdk-configuration.browser-intake-ap1-datadoghq.com")
    }

    func testAP2RemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.ap2.remoteConfigurationHost, "sdk-configuration.browser-intake-ap2-datadoghq.com")
    }

    func testUS1FedRemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.us1_fed.remoteConfigurationHost, "sdk-configuration.browser-intake-ddog-gov.com")
    }

    func testUS2FedRemoteConfigurationHost() {
        XCTAssertEqual(DatadogSite.us2_fed.remoteConfigurationHost, "sdk-configuration.browser-intake-us2-ddog-gov.com")
    }
}
