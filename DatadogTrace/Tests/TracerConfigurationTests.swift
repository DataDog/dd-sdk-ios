/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogTrace

class TracerConfigurationTests: XCTestCase {
    private var core: SingleFeatureCoreMock<DatadogTraceFeature>! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = .init(context: .mockRandom())
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testDefaultTracer() throws {
        DatadogTracer.initialize(in: core)
        let tracer = DatadogTracer.shared(in: core).dd

        XCTAssertNotNil(tracer.core)
        XCTAssertNil(tracer.configuration.serviceName)
        XCTAssertFalse(tracer.configuration.sendNetworkInfo)
        XCTAssertTrue(tracer.contextReceiver.bundleWithRUM)
    }

    func testDefaultTracerWithRUMDisabled() {
        DatadogTracer.initialize(in: core, configuration: .init(bundleWithRUM: false))
        let tracer = DatadogTracer.shared(in: core).dd
        XCTAssertFalse(tracer.contextReceiver.bundleWithRUM)
    }

    func testCustomizedTracer() throws {
        DatadogTracer.initialize(
            in: core,
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true,
                bundleWithRUM: false
            )
        )

        let tracer = DatadogTracer.shared(in: core).dd

        XCTAssertNotNil(tracer.core)
        XCTAssertEqual(tracer.configuration.serviceName, "custom-service-name")
        XCTAssertTrue(tracer.configuration.sendNetworkInfo)
        XCTAssertFalse(tracer.contextReceiver.bundleWithRUM)
    }
}
