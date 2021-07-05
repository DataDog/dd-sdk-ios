/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracerConfigurationTests: XCTestCase {
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()

    override func setUp() {
        super.setUp()
        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.2.3",
                    serviceName: "service-name",
                    environment: "tests"
                )
            ),
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            ),
            loggingFeature: .mockNoOp()
        )
    }

    override func tearDown() {
        TracingFeature.instance?.deinitialize()
        super.tearDown()
    }

    func testDefaultTracer() throws {
        let tracer = Tracer.initialize(
            configuration: .init()
        ).dd

        XCTAssertNil(tracer.rumContextIntegration)

        let feature = TracingFeature.instance!
        XCTAssertEqual((tracer.spanOutput as? SpanFileOutput)?.environment, "tests")
        XCTAssertEqual(tracer.spanBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracer.spanBuilder.serviceName, "service-name")
        XCTAssertTrue(tracer.spanBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertNil(tracer.spanBuilder.networkConnectionInfoProvider)
        XCTAssertNil(tracer.spanBuilder.carrierInfoProvider)

        XCTAssertTrue(
            tracer.logOutput?.loggingOutput is LogFileOutput,
            "When Logging feature is enabled Tracer should use logger pointing to `LogFileOutput`."
        )
        let tracingLogBuilder = try XCTUnwrap(tracer.logOutput?.logBuilder)
        XCTAssertEqual(tracingLogBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracingLogBuilder.environment, "tests")
        XCTAssertEqual(tracingLogBuilder.serviceName, "service-name")
        XCTAssertEqual(tracingLogBuilder.loggerName, "trace")
        XCTAssertTrue(tracingLogBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertNil(tracingLogBuilder.networkConnectionInfoProvider)
        XCTAssertNil(tracingLogBuilder.carrierInfoProvider)
    }

    func testDefaultTracerWithRUMEnabled() {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        let tracer1 = Tracer.initialize(configuration: .init()).dd
        XCTAssertNotNil(tracer1.rumContextIntegration)

        let tracer2 = Tracer.initialize(configuration: .init(bundleWithRUM: false)).dd
        XCTAssertNil(tracer2.rumContextIntegration)
    }

    func testCustomizedTracer() throws {
        let tracer = Tracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true,
                bundleWithRUM: false
            )
        ).dd

        XCTAssertNil(tracer.rumContextIntegration)

        let feature = TracingFeature.instance!
        XCTAssertEqual((tracer.spanOutput as? SpanFileOutput)?.environment, "tests")
        XCTAssertEqual(tracer.spanBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracer.spanBuilder.serviceName, "custom-service-name")
        XCTAssertTrue(tracer.spanBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(tracer.spanBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(tracer.spanBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)

        XCTAssertTrue(
            tracer.logOutput?.loggingOutput is LogFileOutput,
            "When Logging feature is enabled Tracer should use logger pointing to `LogFileOutput`."
        )
        let tracingLogBuilder = try XCTUnwrap(tracer.logOutput?.logBuilder)
        XCTAssertEqual(tracingLogBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracingLogBuilder.environment, "tests")
        XCTAssertEqual(tracingLogBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(tracingLogBuilder.loggerName, "trace")
        XCTAssertTrue(tracingLogBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(tracingLogBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(tracingLogBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
    }
}
