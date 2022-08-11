/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMMonitorConfigurationTests: XCTestCase {
    private let userInfoProvider: UserInfoProvider = .mockAny()
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()

    func testRUMMonitorConfiguration() throws {
        let expectation = expectation(description: "open feature scope")

        let core = DatadogCoreMock(
            context: .mockWith(
                service: "service-name",
                env: "tests",
                version: "1.2.3",
                sdkVersion: "3.4.5",
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider,
                userInfoProvider: userInfoProvider
            )
        )
        defer { core.flush() }

        let feature: RUMFeature = .mockByRecordingRUMEventMatchers(
            featureConfiguration: .mockWith(
                applicationID: "rum-123",
                sessionSampler: Sampler(samplingRate: 42.5)
            )
        )
        core.register(feature: feature)

        let monitor = RUMMonitor.initialize(in: core).dd

        let dependencies = monitor.applicationScope.dependencies
        monitor.core.v1.scope(for: RUMFeature.self)?.eventWriteContext { context, _ in
            XCTAssertTrue(context.userInfoProvider === userInfoProvider)
            XCTAssertTrue(context.networkConnectionInfoProvider as AnyObject === networkConnectionInfoProvider as AnyObject)
            XCTAssertTrue(context.carrierInfoProvider as AnyObject === carrierInfoProvider as AnyObject)

            XCTAssertEqual(context.service, "service-name")
            XCTAssertEqual(context.version, "1.2.3")
            XCTAssertEqual(context.sdkVersion, "3.4.5")

            expectation.fulfill()
        }

        XCTAssertEqual(dependencies.sessionSampler.samplingRate, 42.5)
        XCTAssertEqual(monitor.applicationScope.context.rumApplicationID, "rum-123")
        waitForExpectations(timeout: 0.5)
    }
}
