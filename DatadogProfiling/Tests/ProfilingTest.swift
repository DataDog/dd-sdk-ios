/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling

class ProfilingTest: XCTestCase {
    func testProfilingConfiguration() {
        // Given
        let configuration = Profiling.Configuration(customEndpoint: .mockRandom())

        let core = SingleFeatureCoreMock<ProfilerFeature>()

        // When
        Profiling.enable(with: configuration, in: core)

        // Then
        let feature = core.feature(named: ProfilerFeature.name, type: ProfilerFeature.self)
        let requestBuilder = feature?.requestBuilder as? RequestBuilder
        XCTAssertEqual(requestBuilder?.customUploadURL, configuration.customEndpoint)
    }

    func testProfiling_writeEventAndPprofData() {
        // Given
        let profile = Profile(
            start: .mockRandomInThePast(),
            end: Date(),
            pprof: .mockRandom()
        )

        let profiler = MockProfiler(profile: profile)
        let feature = ProfilerFeature(
            profiler: profiler,
            requestBuilder: FeatureRequestBuilderMock(),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        let core = SingleFeatureCoreMock(feature: feature)

        // When
        Profiling.stop(in: core)

        // Then
        let event = core.metadata(ofType: ProfileEvent.self).first
        XCTAssertEqual(event?.start, profile.start)
        XCTAssertEqual(event?.end, profile.end)
        XCTAssertEqual(event?.family, "ios")
        XCTAssertEqual(event?.runtime, "ios")
        XCTAssertEqual(event?.version, "4")
        XCTAssertEqual(event?.attachments, ["wall.pprof"])
        XCTAssertEqual(event?.tags, "service:abc,version:abc,env:abc,source:abc,language:swift,format:pprof,remote_symbols:yes")

        let pprof = core.events(ofType: Data.self).first
        XCTAssertEqual(pprof, profile.pprof)
    }

    func testProfiling_writeEventWithRUMContext() {
        // Given
        let profile = Profile(
            start: .mockRandomInThePast(),
            end: Date(),
            pprof: .mockRandom()
        )

        let profiler = MockProfiler(profile: profile)
        let feature = ProfilerFeature(
            profiler: profiler,
            requestBuilder: FeatureRequestBuilderMock(),
            messageReceiver: NOPFeatureMessageReceiver()
        )

        let rum = RUMCoreContext(
            applicationID: .mockRandom(),
            sessionID: .mockRandom(),
            viewID: .mockRandom()
        )

        let core = SingleFeatureCoreMock(
            context: .mockWith(
                additionalContext: [rum]
            ),
            feature: feature
        )

        // When
        Profiling.stop(in: core)

        // Then
        let event = core.metadata(ofType: ProfileEvent.self).first
        XCTAssertEqual(event?.application?.id, rum.applicationID)
        XCTAssertEqual(event?.session?.id, rum.sessionID)
        XCTAssertEqual(event?.view?.id.first, rum.viewID)
    }
}
