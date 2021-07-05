/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import struct Datadog.DDGlobal
@testable import class Datadog.TracingFeature
@testable import class Datadog.DDNoopRUMMonitor
@testable import class Datadog.Tracer
@testable import struct Datadog.DDNoopTracer
@testable import class Datadog.RUMFeature
@testable import class Datadog.RUMMonitor
@testable import DatadogObjc

class DDGlobalTests: XCTestCase {
    // MARK: - Test Global Tracer

    func testWhenTracerIsNotSet_itReturnsNoOpImplementation() {
        XCTAssertTrue(DatadogObjc.DDGlobal.sharedTracer.swiftTracer is Datadog.DDNoopTracer)
        XCTAssertTrue(Datadog.DDGlobal.sharedTracer is Datadog.DDNoopTracer)
    }

    func testWhenTracerIsSet_itSetsSwiftImplementation() {
        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance?.deinitialize() }

        let previousGlobal = (
            objc: DatadogObjc.DDGlobal.sharedTracer,
            swift: Datadog.DDGlobal.sharedTracer
        )
        defer {
            DatadogObjc.DDGlobal.sharedTracer = previousGlobal.objc
            Datadog.DDGlobal.sharedTracer = previousGlobal.swift
        }

        // When
        DatadogObjc.DDGlobal.sharedTracer = DatadogObjc.DDTracer(configuration: DDTracerConfiguration())

        // Then
        XCTAssertTrue(Datadog.DDGlobal.sharedTracer is Datadog.Tracer)
    }

    // MARK: - Test Global RUMMonitor

    func testWhenRUMMonitorIsNotSet_itReturnsNoOpImplementation() {
        XCTAssertTrue(DatadogObjc.DDGlobal.rum.swiftRUMMonitor is Datadog.DDNoopRUMMonitor)
        XCTAssertTrue(Datadog.DDGlobal.rum is Datadog.DDNoopRUMMonitor)
    }

    func testWhenRUMMonitorIsSet_itSetsSwiftImplementation() {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        let previousGlobal = (
            objc: DatadogObjc.DDGlobal.rum,
            swift: Datadog.DDGlobal.rum
        )
        defer {
            DatadogObjc.DDGlobal.rum = previousGlobal.objc
            Datadog.DDGlobal.rum = previousGlobal.swift
        }

        // When
        DatadogObjc.DDGlobal.rum = DatadogObjc.DDRUMMonitor()

        // Then
        XCTAssertTrue(Datadog.DDGlobal.rum is Datadog.RUMMonitor)
    }
}
