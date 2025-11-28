/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports
import TestUtilities

@testable import DatadogProfiling
@testable import DatadogRUM

final class ProfilingRUMIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        ctor_profiler_stop()
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)

        let launchInfo: LaunchInfo = .mockWith(processLaunchDate: Date())
        core = DatadogCoreProxy(
            context: .mockWith(
                trackingConsent: .granted,
                launchInfo: launchInfo
            )
        )
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        ctor_profiler_stop()
        delete_profiling_defaults()

        super.tearDown()
    }

    func testProfilingWithoutRUM_itDoesNotSendAProfileEvent() throws {
        // Given
        var frameInfoProvider: FrameInfoProviderMock? = nil
        var config = RUM.Configuration(applicationID: "mock-application-id")
        config.dateProvider = DateProviderMock()
        config.mediaTimeProvider = MediaTimeProviderMock(current: 0)
        config.frameInfoProviderFactory = {
            frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
            return frameInfoProvider!
        }

        // When
        Profiling.enable(in: self.core)

        // Then
        let pprofData = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: ProfilerFeature.name, ofType: Data.self))
        XCTAssertTrue(pprofData.isEmpty)
        let profilingEvents = try XCTUnwrap(core.waitAndReturnEventsMetadata(ofFeature: ProfilerFeature.name, ofType: ProfileEvent.self))
        XCTAssertTrue(profilingEvents.isEmpty)

        XCTAssertTrue(is_profiling_enabled())
    }

    func testWhenRUMSendsTTIDMessage_itSendsAProfileEvent() throws {
        // Given
        var frameInfoProvider: FrameInfoProviderMock? = nil
        var config = RUM.Configuration(applicationID: "mock-application-id")
        config.dateProvider = DateProviderMock()
        config.mediaTimeProvider = MediaTimeProviderMock(current: 0)
        config.frameInfoProviderFactory = {
            frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
            return frameInfoProvider!
        }

        // When
        RUM.enable(with: config, in: self.core)
        Profiling.enable(in: self.core)

        frameInfoProvider?.triggerCallback(interval: 1)

        // Then
        let rumVitalEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(rumVitalEvents.count, 1)
        let ttidVitalEvent = try XCTUnwrap(rumVitalEvents.first)
        XCTAssertEqual(ttidVitalEvent.dd.profiling?.status, .running)
        XCTAssertEqual(ttidVitalEvent.vital.appLaunchMetric, .ttid)

        let pprofData = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: ProfilerFeature.name, ofType: Data.self))
        XCTAssertEqual(pprofData.count, 1)

        let profilingEvents = try XCTUnwrap(core.waitAndReturnEventsMetadata(ofFeature: ProfilerFeature.name, ofType: ProfileEvent.self))
        XCTAssertEqual(profilingEvents.count, 1)
        let profilingEvent = try XCTUnwrap(profilingEvents.first)
        XCTAssertEqual(profilingEvent.family, "ios")
        XCTAssertEqual(profilingEvent.runtime, "ios")
        XCTAssertEqual(profilingEvent.attachments, [ProfileEvent.Constants.wallFilename])
        XCTAssertFalse(profilingEvent.tags.isEmpty)
        XCTAssertFalse(profilingEvent.additionalAttributes!.isEmpty)

        XCTAssertTrue(is_profiling_enabled())
    }

    func testWhenRUMDoesNotSendTTIDMessage_itDoesNotSendAProfileEvent() throws {
        // Given
        var frameInfoProvider: FrameInfoProviderMock? = nil
        var config = RUM.Configuration(applicationID: "mock-application-id")
        config.dateProvider = DateProviderMock()
        config.mediaTimeProvider = MediaTimeProviderMock(current: 0)
        config.frameInfoProviderFactory = {
            frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
            return frameInfoProvider!
        }

        // When
        RUM.enable(with: config, in: self.core)
        Profiling.enable(in: self.core)

        // Then
        let rumVitalEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMVitalAppLaunchEvent.self)
        XCTAssertTrue(rumVitalEvents.isEmpty)

        let pprofData = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: ProfilerFeature.name, ofType: Data.self))
        XCTAssertTrue(pprofData.isEmpty)
        let profilingEvents = try XCTUnwrap(core.waitAndReturnEventsMetadata(ofFeature: ProfilerFeature.name, ofType: ProfileEvent.self))
        XCTAssertTrue(profilingEvents.isEmpty)

        XCTAssertTrue(is_profiling_enabled())
    }
}
