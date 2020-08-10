/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMMonitorConfigurationTests: XCTestCase {
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()
    private var mockServer: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()

        mockServer = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: mockServer,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationVersion: "1.2.3",
                serviceName: "service-name",
                environment: "tests"
            ),
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }

    override func tearDown() {
        mockServer.waitAndAssertNoRequestsSent()
        RUMFeature.instance = nil
        mockServer = nil

        temporaryDirectory.delete()
        super.tearDown()
    }

    func testDefaultRUMMonitor() throws {
        let monitor = RUMMonitor.initialize(rumApplicationID: .mockAny())

        let feature = try XCTUnwrap(RUMFeature.instance)
        let rumEventBuilder = monitor.applicationScope.dependencies.eventBuilder

        XCTAssertTrue(rumEventBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(rumEventBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(rumEventBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
    }

    func testCustomizedRUMMonitor() {
        // TODO: RUMM-614 Test customized `RUMMonitor`
    }
}
