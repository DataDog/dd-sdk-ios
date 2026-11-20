/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogProfiling

final class DDProfilingTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private let instanceName = "profiling-test"

    override func setUp() {
        super.setUp()
        core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        CoreRegistry.unregisterDefault()
        CoreRegistry.unregisterInstance(named: instanceName)
        core = nil
        super.tearDown()
    }

    func testEnableWithConfiguration() throws {
        let customEndpoint: URL = .mockRandom()
        let configuration = objc_ProfilingConfiguration(
            customEndpoint: customEndpoint,
            applicationLaunchSampleRate: 0,
            continuousSampleRate: 0
        )

        objc_Profiling.enable(with: configuration)

        let feature = try XCTUnwrap(core.get(feature: ProfilerFeature.self))
        let requestBuilder = try XCTUnwrap(feature.requestBuilder as? RequestBuilder)
        XCTAssertEqual(requestBuilder.customUploadURL, customEndpoint)
        XCTAssertFalse(feature.profilingSamplerProvider.isContinuousProfilingConfigured)
    }

    func testEnableOnNamedInstance() {
        let namedCore = FeatureRegistrationCoreMock()
        CoreRegistry.register(namedCore, named: instanceName)

        objc_Profiling.enable(
            with: .init(applicationLaunchSampleRate: 0, continuousSampleRate: 0),
            instanceName: instanceName
        )

        XCTAssertNotNil(namedCore.get(feature: ProfilerFeature.self))
        XCTAssertNil(core.get(feature: ProfilerFeature.self))
    }

    func testEnableWithNilInstanceNameUsesDefaultInstance() {
        objc_Profiling.enable(
            with: .init(applicationLaunchSampleRate: 0, continuousSampleRate: 0),
            instanceName: nil
        )

        XCTAssertNotNil(core.get(feature: ProfilerFeature.self))
    }

    func testEnableBeforeInitializationPrintsError() {
        CoreRegistry.unregisterDefault()
        let printFunction = PrintFunctionSpy()
        let originalConsolePrint = consolePrint
        consolePrint = printFunction.print
        defer { consolePrint = originalConsolePrint }

        objc_Profiling.enable()

        XCTAssertTrue(core.registeredFeatures.isEmpty)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `Profiling.enable(with:)`."
        )
    }

    func testEnableOnUnknownInstanceDoesNotUseDefaultInstance() {
        let printFunction = PrintFunctionSpy()
        let originalConsolePrint = consolePrint
        consolePrint = printFunction.print
        defer { consolePrint = originalConsolePrint }

        objc_Profiling.enable(with: .init(), instanceName: instanceName)

        XCTAssertTrue(core.registeredFeatures.isEmpty)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `Profiling.enable(with:)`."
        )
    }

    func testEnablingTwiceKeepsOriginalFeature() throws {
        objc_Profiling.enable(with: .init(applicationLaunchSampleRate: 0, continuousSampleRate: 0))
        let feature = try XCTUnwrap(core.get(feature: ProfilerFeature.self))

        objc_Profiling.enable(with: .init(customEndpoint: .mockRandom()))

        XCTAssertTrue(core.get(feature: ProfilerFeature.self) === feature)
        XCTAssertEqual(core.registeredFeatures.count, 1)
    }

    func testEnablingOnAnotherInstanceKeepsOriginalFeature() throws {
        let namedCore = FeatureRegistrationCoreMock()
        CoreRegistry.register(namedCore, named: instanceName)
        objc_Profiling.enable(with: .init(applicationLaunchSampleRate: 0, continuousSampleRate: 0))
        let feature = try XCTUnwrap(core.get(feature: ProfilerFeature.self))

        objc_Profiling.enable(with: .init(), instanceName: instanceName)

        XCTAssertTrue(core.get(feature: ProfilerFeature.self) === feature)
        XCTAssertNil(namedCore.get(feature: ProfilerFeature.self))
    }
}

#endif
