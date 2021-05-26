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
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.2.3",
                    serviceName: "service-name",
                    environment: "tests"
                ),
                applicationID: "rum-123",
                sessionSamplingRate: 42.5
            ),
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        )
        defer { RUMFeature.instance?.deinitialize() }

        let monitor = RUMMonitor.initialize().dd

        let feature = try XCTUnwrap(RUMFeature.instance)
        let scopeDependencies = monitor.applicationScope.dependencies

        XCTAssertTrue(scopeDependencies.userInfoProvider.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(scopeDependencies.connectivityInfoProvider.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(scopeDependencies.connectivityInfoProvider.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
        XCTAssertEqual(monitor.applicationScope.samplingRate, 42.5)
        XCTAssertEqual(monitor.applicationScope.context.rumApplicationID, "rum-123")
    }
}
