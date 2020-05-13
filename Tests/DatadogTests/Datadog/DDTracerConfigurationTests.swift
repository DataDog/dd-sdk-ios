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
        let tracer = DDTracer.initialize(configuration: .init()).dd

        guard let spanBuilder = (tracer.spanOutput as? SpanFileOutput)?.spanBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(spanBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(spanBuilder.serviceName, "service-name")
        XCTAssertEqual(spanBuilder.environment, "tests")
        XCTAssertNotNil(spanBuilder.networkConnectionInfoProvider) // TODO: RUMM-422 Assert it's `nil` by default
        XCTAssertNotNil(spanBuilder.carrierInfoProvider) // TODO: RUMM-422 Assert it's `nil` by default
    }

    func testCustomizedTracer() {
        let tracer = DDTracer.initialize(
            configuration: .init(serviceName: "custom-service-name")
        ).dd

        guard let spanBuilder = (tracer.spanOutput as? SpanFileOutput)?.spanBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(spanBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(spanBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(spanBuilder.environment, "tests")
        XCTAssertNotNil(spanBuilder.networkConnectionInfoProvider) // TODO: RUMM-422 Disable network info and assert it's `nil`
        XCTAssertNotNil(spanBuilder.carrierInfoProvider) // TODO: RUMM-422 Disable network info and assert it's `nil`
    }
}

class DDTracerErrorTests: XCTestCase {
    func testGivenDatadogNotInitialized_whenInitializingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer.initialize(configuration: .init())
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `DDTracer.initialize()`."
        )
        XCTAssertTrue(tracer is DDNoopTracer)
    }

    func testGivenDatadogNotInitialized_whenUsingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer(spanOutput: SpanOutputMock())
        let fixtures: [(() -> Void, String)] = [
            ({ _ = tracer.startSpan(operationName: .mockAny()) },
             "`Datadog.initialize()` must be called prior to `startSpan(...)`."),
        ]

        fixtures.forEach { tracerMethod, expectedConsoleError in
            tracerMethod()
            XCTAssertEqual(printFunction.printedMessage, "🔥 Datadog SDK usage error: \(expectedConsoleError)")
        }
    }
}
