/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDTracerConfigurationTests: XCTestCase {
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()
    private var mockServer: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()

        mockServer = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: mockServer,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationVersion: "1.2.3",
                serviceName: "service-name",
                environment: "tests"
            ),
            loggingFeature: .mockNoOp(temporaryDirectory: temporaryDirectory),
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }

    override func tearDown() {
        mockServer.waitAndAssertNoRequestsSent()
        TracingFeature.instance = nil
        mockServer = nil

        temporaryDirectory.delete()
        super.tearDown()
    }

    func testDefaultTracer() {
        let tracer = DDTracer.initialize(
            configuration: .init()
        ).dd

        guard let spanBuilder = (tracer.spanOutput as? SpanFileOutput)?.spanBuilder else {
            XCTFail()
            return
        }

        let feature = TracingFeature.instance!
        XCTAssertEqual(spanBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(spanBuilder.environment, "tests")
        XCTAssertEqual(spanBuilder.serviceName, "service-name")
        XCTAssertTrue(spanBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertNil(spanBuilder.networkConnectionInfoProvider)
        XCTAssertNil(spanBuilder.carrierInfoProvider)

        guard let tracingLogBuilder = (tracer.logOutput?.loggingOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(tracingLogBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracingLogBuilder.environment, "tests")
        XCTAssertEqual(tracingLogBuilder.serviceName, "service-name")
        XCTAssertEqual(tracingLogBuilder.loggerName, "trace")
        XCTAssertTrue(tracingLogBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertNil(tracingLogBuilder.networkConnectionInfoProvider)
        XCTAssertNil(tracingLogBuilder.carrierInfoProvider)
    }

    func testCustomizedTracer() {
        let tracer = DDTracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true
            )
        ).dd

        guard let spanBuilder = (tracer.spanOutput as? SpanFileOutput)?.spanBuilder else {
            XCTFail()
            return
        }

        let feature = TracingFeature.instance!
        XCTAssertEqual(spanBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(spanBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(spanBuilder.environment, "tests")
        XCTAssertTrue(spanBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(spanBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(spanBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)

        guard let tracingLogBuilder = (tracer.logOutput?.loggingOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(tracingLogBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(tracingLogBuilder.environment, "tests")
        XCTAssertEqual(tracingLogBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(tracingLogBuilder.loggerName, "trace")
        XCTAssertTrue(tracingLogBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(tracingLogBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(tracingLogBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
    }
}
