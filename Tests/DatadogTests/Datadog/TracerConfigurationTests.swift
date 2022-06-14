/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracerConfigurationTests: XCTestCase {
    private let userInfoProvider: UserInfoProvider = .mockAny()
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()
    private lazy var core = DatadogCoreMock(
        context: .mockWith(
            configuration: .mockWith(
                applicationVersion: "1.2.3",
                serviceName: "service-name",
                environment: "tests"
            ),
            dependencies: .mockWith(
                userInfoProvider: userInfoProvider,
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        )
    )

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
        let feature: TracingFeature = .mockNoOp()
        core.register(feature: feature)
    }

    override func tearDown() {
        core.flush()
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testDefaultTracer() throws {
        let tracer = Tracer.initialize(configuration: .init(), in: core).dd

        XCTAssertNotNil(tracer.core)
        XCTAssertNil(tracer.configuration.serviceName)
        XCTAssertFalse(tracer.configuration.sendNetworkInfo)
        XCTAssertNil(tracer.rumContextIntegration)
    }

    func testDefaultTracerWithRUMEnabled() {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let tracer1 = Tracer.initialize(configuration: .init(), in: core).dd
        XCTAssertNotNil(tracer1.rumContextIntegration)

        let tracer2 = Tracer.initialize(configuration: .init(bundleWithRUM: false), in: core).dd
        XCTAssertNil(tracer2.rumContextIntegration)
    }

    func testCustomizedTracer() throws {
        let tracer = Tracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true,
                bundleWithRUM: false
            ),
            in: core
        ).dd

        XCTAssertNotNil(tracer.core)
        XCTAssertEqual(tracer.configuration.serviceName, "custom-service-name")
        XCTAssertTrue(tracer.configuration.sendNetworkInfo)
        XCTAssertNil(tracer.rumContextIntegration)
    }

    func testWhenLoggingFeatureIsEnabled_itUsesLogsIntegration() throws {
        // When
        core.register(feature: LoggingFeature.mockNoOp())

        // Then
        let tracer = Tracer.initialize(configuration: .init(), in: core).dd
        XCTAssertTrue(
            tracer.loggingIntegration?.loggingOutput is LogFileOutput,
            "When Logging feature is enabled Tracer should use logger pointing to `LogFileOutput`."
        )
        let tracingLogBuilder = try XCTUnwrap(tracer.loggingIntegration?.logBuilder)
        XCTAssertEqual(tracingLogBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracingLogBuilder.environment, "tests")
        XCTAssertEqual(tracingLogBuilder.serviceName, "service-name")
        XCTAssertEqual(tracingLogBuilder.loggerName, "trace")
        XCTAssertNil(tracingLogBuilder.networkConnectionInfoProvider)
        XCTAssertNil(tracingLogBuilder.carrierInfoProvider)
        XCTAssertTrue(tracer.loggingIntegration?.logBuilder.userInfoProvider === userInfoProvider)
    }

    func testWhenLoggingFeatureIsNotEnabled_itDoesNotUseLogsIntegration() throws {
        // When
        XCTAssertNil(core.v1.feature(LoggingFeature.self))

        // Then
        let tracer = Tracer.initialize(configuration: .init(), in: core).dd
        XCTAssertNil(tracer.loggingIntegration)
    }
}
