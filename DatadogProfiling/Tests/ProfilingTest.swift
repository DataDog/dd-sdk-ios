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
    func testProfilingConfiguration() throws {
        // Given
        let configuration = Profiling.Configuration(customEndpoint: .mockRandom())
        let core = SingleFeatureCoreMock<ProfilerFeature>()
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        defer { ctor_profiler_destroy() }

        // When
        Profiling.enable(with: configuration, in: core)

        // Then
        let feature = core.feature(named: ProfilerFeature.name, type: ProfilerFeature.self)
        let requestBuilder = feature?.requestBuilder as? RequestBuilder
        XCTAssertEqual(feature?.performanceOverride?.maxFileSize, .min)
        XCTAssertEqual(requestBuilder?.customUploadURL, configuration.customEndpoint)
        XCTAssertEqual(feature?.telemetryController.sampleRate, 20)

        let context = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(context.status, .running)
    }

    // MARK: - Remote Configuration

    func testWhenEnabledWithRemoteConfiguration_itRegistersProfilerFeature() throws {
        // Given a remote `profiling` namespace overriding the in-code sample rate
        let configuration = Profiling.Configuration(applicationLaunchSampleRate: 5)
        let core = SingleFeatureCoreMock<ProfilerFeature>()
        core.remoteConfiguration = .mockWith(profiling: .mockWith(applicationLaunchSampleRate: 100))
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        defer { ctor_profiler_destroy() }

        // When
        Profiling.enable(with: configuration, in: core)

        // Then — the merge is applied at enable time and the feature is registered without error.
        // `applicationLaunchSampleRate` override correctness is verified at the configuration level in
        // `ProfilingConfiguration_RemoteConfigurationTests` (the feature persists the sample rate to a
        // shared UserDefaults suite, which makes enable-level assertions on it flaky).
        XCTAssertNotNil(core.feature(named: ProfilerFeature.name, type: ProfilerFeature.self))
    }
}

#endif
