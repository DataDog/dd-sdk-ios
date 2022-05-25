/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import  Datadog
@testable import DatadogObjc

class DDGlobalTests: XCTestCase {
    let core = DatadogCoreMock()

    override func setUp() {
        super.setUp()
        defaultDatadogCore = core
    }

    override func tearDown() {
        core.flush()
        defaultDatadogCore = NOOPDatadogCore()
        super.tearDown()
    }
    // MARK: - Test Global Tracer

    func testWhenTracerIsNotSet_itReturnsNoOpImplementation() {
        XCTAssertTrue(DatadogObjc.DDGlobal.sharedTracer.swiftTracer is DDNoopTracer)
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)
    }

    func testWhenTracerIsSet_itSetsSwiftImplementation() {
        let tracing: TracingFeature = .mockNoOp()
        defaultDatadogCore.register(feature: tracing)

        let previousGlobal = (
            objc: DatadogObjc.DDGlobal.sharedTracer,
            swift: Global.sharedTracer
        )
        defer {
            DatadogObjc.DDGlobal.sharedTracer = previousGlobal.objc
            Global.sharedTracer = previousGlobal.swift
        }

        // When
        DatadogObjc.DDGlobal.sharedTracer = DatadogObjc.DDTracer(configuration: DDTracerConfiguration())

        // Then
        XCTAssertTrue(Global.sharedTracer is Tracer)
    }

    // MARK: - Test Global RUMMonitor

    func testWhenRUMMonitorIsNotSet_itReturnsNoOpImplementation() {
        XCTAssertTrue(DatadogObjc.DDGlobal.rum.swiftRUMMonitor is DDNoopRUMMonitor)
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)
    }

    func testWhenRUMMonitorIsSet_itSetsSwiftImplementation() {
        let rum: RUMFeature = .mockNoOp()
        defaultDatadogCore.register(feature: rum)

        let previousGlobal = (
            objc: DatadogObjc.DDGlobal.rum,
            swift: Global.rum
        )
        defer {
            DatadogObjc.DDGlobal.rum = previousGlobal.objc
            Global.rum = previousGlobal.swift
        }

        // When
        DatadogObjc.DDGlobal.rum = DatadogObjc.DDRUMMonitor()

        // Then
        XCTAssertTrue(Global.rum is RUMMonitor)
    }
}
