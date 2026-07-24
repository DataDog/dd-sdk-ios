/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling
import DatadogMachProfiler

class ProfilingTest: XCTestCase {
    private let primaryInstanceName = "primary"
    private let secondaryInstanceName = "secondary"

    override func setUp() {
        super.setUp()
        CoreRegistry.unregisterDefault()
        CoreRegistry.unregisterInstance(named: primaryInstanceName)
        CoreRegistry.unregisterInstance(named: secondaryInstanceName)
        dd_profiler_stop()
        dd_profiler_destroy()
    }

    override func tearDown() {
        CoreRegistry.unregisterDefault()
        CoreRegistry.unregisterInstance(named: primaryInstanceName)
        CoreRegistry.unregisterInstance(named: secondaryInstanceName)
        dd_profiler_stop()
        dd_profiler_destroy()
        super.tearDown()
    }

    func testProfilingConfiguration() throws {
        // Given
        let configuration = Profiling.Configuration(customEndpoint: .mockRandom())
        let core = SingleFeatureCoreMock<ProfilerFeature>()
        XCTAssertEqual(dd_profiler_start(), 1)
        defer { dd_profiler_destroy() }

        // When
        Profiling.enable(with: configuration, in: core)

        // Then
        let feature = core.feature(named: ProfilerFeature.name, type: ProfilerFeature.self)
        let requestBuilder = feature?.requestBuilder as? RequestBuilder
        XCTAssertEqual(feature?.performanceOverride?.maxFileSize, ProfilerFeature.Constants.maxFileSize)
        XCTAssertEqual(requestBuilder?.customUploadURL, configuration.customEndpoint)
        XCTAssertEqual(feature?.telemetryController.sampleRate, 20)

        let context = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(context.status, .running)
    }

    func testWhenEnabledInMultipleCoreInstances_itPrintsErrorAndKeepsFirstFeature() {
        // Given
        let firstCore = FeatureRegistrationCoreMock()
        let secondCore = FeatureRegistrationCoreMock()
        CoreRegistry.register(firstCore, named: primaryInstanceName)
        CoreRegistry.register(secondCore, named: secondaryInstanceName)

        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        Profiling.enable(in: firstCore)
        Profiling.enable(in: secondCore)

        // Then
        XCTAssertNotNil(firstCore.get(feature: ProfilerFeature.self))
        XCTAssertNil(secondCore.get(feature: ProfilerFeature.self))
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Profiling is already enabled in SDK instance 'primary' and does not support multiple instances. The existing instance will continue to be used."
        )
    }
}

#endif
