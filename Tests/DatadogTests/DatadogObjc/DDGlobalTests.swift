/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import DatadogInternal
@testable import DatadogTrace
@testable import DatadogRUM
@testable import Datadog
@testable import DatadogObjc

class DDGlobalTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        CoreRegistry.unregisterDefault()
        super.tearDown()
    }
    // MARK: - Test Global Tracer

    func testWhenTracerIsNotSet_itReturnsNoOpImplementation() {
        XCTAssertTrue(DatadogObjc.DDGlobal.sharedTracer.swiftTracer is DDNoopTracer)
    }

    func testWhenTracerIsSet_itSetsSwiftImplementation() {
        // When
        DatadogObjc.DDTracer.initialize(configuration: .init())

        // Then
        XCTAssertTrue(DatadogObjc.DDTracer.shared.swiftTracer is DatadogTracer)
    }

    // MARK: - Test Global RUMMonitor

    func testWhenDDRUMMonitorIsNotInitailized_itReturnsNoOpImplementation() {
        XCTAssertTrue(DatadogObjc.DDGlobal.rum.swiftRUMMonitor is NOPMonitor)
    }

    func testWhenDDRUMMonitorIsInitailized_itSetsSwiftImplementation() {
        // When
        RUM.enable(with: .mockAny(), in: core)
        // Then
        XCTAssertTrue(DatadogObjc.DDGlobal.rum.swiftRUMMonitor is Monitor)
    }
}
