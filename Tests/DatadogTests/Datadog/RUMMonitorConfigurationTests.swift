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
        let core = DatadogCoreMock(
            context: .mockWith(
                configuration: .mockWith(
                    applicationVersion: "1.2.3",
                    serviceName: "service-name",
                    environment: "tests",
                    sdkVersion: "3.4.5"
                ),
                dependencies: .mockWith(
                    userInfoProvider: userInfoProvider,
                    networkConnectionInfoProvider: networkConnectionInfoProvider,
                    carrierInfoProvider: carrierInfoProvider
                )
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

        let scopeDependencies = monitor.applicationScope.dependencies

        XCTAssertTrue(scopeDependencies.userInfoProvider.userInfoProvider === userInfoProvider)
        XCTAssertTrue(scopeDependencies.connectivityInfoProvider.networkConnectionInfoProvider as AnyObject === networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(scopeDependencies.connectivityInfoProvider.carrierInfoProvider as AnyObject === carrierInfoProvider as AnyObject)
        XCTAssertEqual(scopeDependencies.sessionSampler.samplingRate, 42.5)
        XCTAssertEqual(scopeDependencies.serviceName, "service-name")
        XCTAssertEqual(scopeDependencies.applicationVersion, "1.2.3")
        XCTAssertEqual(scopeDependencies.sdkVersion, "3.4.5")
        XCTAssertEqual(monitor.applicationScope.context.rumApplicationID, "rum-123")
    }
}
