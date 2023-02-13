/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class RUMMonitorConfigurationTests: XCTestCase {
    private let userIno: UserInfo = .mockAny()
    private let networkConnectionInfo: NetworkConnectionInfo = .mockAny()
    private let carrierInfo: CarrierInfo = .mockAny()

    func testRUMMonitorConfiguration() throws {
        let expectation = expectation(description: "open feature scope")

        let core = DatadogCoreProxy(
            context: .mockWith(
                service: "service-name",
                env: "tests",
                version: "1.2.3",
                sdkVersion: "3.4.5",
                userInfo: userIno,
                networkConnectionInfo: networkConnectionInfo,
                carrierInfo: carrierInfo
            )
        )
        defer { core.flushAndTearDown() }

        let feature: RUMFeature = .mockWith(
            configuration: .mockWith(
                applicationID: "rum-123",
                sessionSampler: Sampler(samplingRate: 42.5)
            )
        )
        core.register(feature: feature)

        let monitor = RUMMonitor.initialize(in: core).dd

        let dependencies = monitor.applicationScope.dependencies
        monitor.core.v1.scope(for: RUMFeature.self)?.eventWriteContext { context, _ in
            DDAssertReflectionEqual(context.userInfo, self.userIno)
            XCTAssertEqual(context.networkConnectionInfo, self.networkConnectionInfo)
            XCTAssertEqual(context.carrierInfo, self.carrierInfo)

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
