/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class TracerConfigurationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockRandom())
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testDefaultTracer() throws {
        let tracer = Tracer.initialize(configuration: .init(), in: core).dd

        XCTAssertNotNil(tracer.core)
        XCTAssertNil(tracer.configuration.serviceName)
        XCTAssertFalse(tracer.configuration.sendNetworkInfo)
        XCTAssertNotNil(tracer.rumIntegration)
    }

    func testDefaultTracerWithRUMEnabled() {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let tracer1 = Tracer.initialize(configuration: .init(), in: core).dd
        XCTAssertNotNil(tracer1.rumIntegration)

        let tracer2 = Tracer.initialize(configuration: .init(bundleWithRUM: false), in: core).dd
        XCTAssertNil(tracer2.rumIntegration)
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
        XCTAssertNil(tracer.rumIntegration)
    }
}
