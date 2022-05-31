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

    func testRUMMonitorConfiguration() throws {
        temporaryDirectory.create()
        defer { temporaryDirectory.delete() }

        let core = DatadogCoreMock()
        defer { core.flush() }

        let feature: RUMFeature = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.2.3",
                    serviceName: "service-name",
                    environment: "tests",
                    sdkVersion: "3.4.5"
                ),
                applicationID: "rum-123",
                sessionSampler: Sampler(samplingRate: 42.5)
            ),
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        )

        core.register(feature: feature)

        let monitor = RUMMonitor.initialize(in: core).dd

        let scopeDependencies = monitor.applicationScope.dependencies

        XCTAssertTrue(scopeDependencies.userInfoProvider.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(scopeDependencies.connectivityInfoProvider.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(scopeDependencies.connectivityInfoProvider.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
        XCTAssertEqual(scopeDependencies.sessionSampler.samplingRate, 42.5)
        XCTAssertEqual(scopeDependencies.serviceName, "service-name")
        XCTAssertEqual(scopeDependencies.applicationVersion, "1.2.3")
        XCTAssertEqual(scopeDependencies.sdkVersion, "3.4.5")
        XCTAssertEqual(monitor.applicationScope.context.rumApplicationID, "rum-123")
    }
}
