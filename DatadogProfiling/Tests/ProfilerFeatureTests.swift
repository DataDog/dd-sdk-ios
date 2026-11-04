/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogInternal
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports
import TestUtilities
@testable import DatadogProfiling

final class ProfilerFeatureTests: XCTestCase {
    private let core: DatadogCoreProtocol = PassthroughCoreMock()
    private let requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    private let telemetryController = ProfilingTelemetryController()

    private var userDefaults: UserDefaults! //swiftlint:disable:this implicitly_unwrapped_optional
    private let suiteName = "ProfilerFeatureTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        dd_profiler_stop()
        dd_profiler_destroy()
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        dd_profiler_stop()
        dd_profiler_destroy()
        super.tearDown()
    }

    func testInit_setsIsEnabledFlagToTrue() {
        // Given
        XCTAssertNil(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY))

        // When
        _ = ProfilerFeature(
            core: core,
            configuration: .init(),
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool, true)
    }

    func testInit_setsMemorySampleRateValue() {
        // Given
        userDefaults.removeObject(forKey: DD_MEMORY_SAMPLE_RATE_KEY)
        let memorySampleRate: SampleRate = 100

        // When
        _ = ProfilerFeature(
            core: core,
            configuration: .init(memorySampleRate: memorySampleRate),
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_MEMORY_SAMPLE_RATE_KEY) as? SampleRate, memorySampleRate)
    }

    func testInit_setsMemorySampleRateValue_whenDisabled() {
        // Given
        userDefaults.removeObject(forKey: DD_MEMORY_SAMPLE_RATE_KEY)

        // When
        _ = ProfilerFeature(
            core: core,
            configuration: .init(memorySampleRate: 0),
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_MEMORY_SAMPLE_RATE_KEY) as? SampleRate, 0)
    }

    /// The persisted rate is what the pre-`main` constructor draws against on the NEXT launch, so it
    /// must carry the same `debugSDK` boost the in-process sampler gets. Persisting the raw rate
    /// instead left a debug session fully sampled in for its own lifetime while the app-launch
    /// window it exists to capture still drew at the configured rate — 1% in a typical E2E setup.
    func testInit_persistsDebugBoostedMemorySampleRate() {
        // Given
        userDefaults.removeObject(forKey: DD_MEMORY_SAMPLE_RATE_KEY)

        var configuration = Profiling.Configuration(memorySampleRate: 1)
        configuration.debugSDK = true

        // When
        _ = ProfilerFeature(
            core: core,
            configuration: configuration,
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(
            userDefaults.value(forKey: DD_MEMORY_SAMPLE_RATE_KEY) as? SampleRate,
            .maxSampleRate,
            "debugSDK must boost the rate persisted for the next launch, not just this session's sampler"
        )
    }

    /// The boost is opt-in-preserving: `debugSDK` must never turn on a feature the customer left at
    /// zero, for this session or the next launch.
    func testInit_debugSDKDoesNotEnableMemoryProfiling_whenUnconfigured() {
        // Given
        userDefaults.removeObject(forKey: DD_MEMORY_SAMPLE_RATE_KEY)

        var configuration = Profiling.Configuration(memorySampleRate: 0)
        configuration.debugSDK = true

        // When
        _ = ProfilerFeature(
            core: core,
            configuration: configuration,
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(
            userDefaults.value(forKey: DD_MEMORY_SAMPLE_RATE_KEY) as? SampleRate,
            0,
            "debugSDK must not silently enable an opt-in feature for the next launch"
        )
    }

    func testInit_setsSampleRateValue() {
        // Given
        userDefaults.setValue(SampleRate(20), forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY)
        let newSampleRate: SampleRate = 23

        // When
        _ = ProfilerFeature(
            core: core,
            configuration: .init(applicationLaunchSampleRate: newSampleRate),
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY) as? SampleRate, newSampleRate)
    }

    func testProfilingSamplerProvider_isDeterministicForSameSessionID() {
        // Given
        let continuousSampleRate: SampleRate = 80
        let sessionUUID = "abcdef01-2345-6789-abcd-ef0123456789"
        let sessionSampler = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: 100)

        let firstProvider = ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate)
        let secondProvider = ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate)

        // When
        firstProvider.updateWith(deterministicSampler: sessionSampler)
        secondProvider.updateWith(deterministicSampler: sessionSampler)
        let firstDecision = firstProvider.continuousProfilingSampled
        let secondDecision = secondProvider.continuousProfilingSampled

        // Then
        XCTAssertEqual(firstDecision, firstProvider.continuousProfilingSampled)
        XCTAssertEqual(firstDecision, secondDecision)
    }

    func testProfilingSamplerProvider_updatesAppLaunchSamplingForRUMSession() {
        let provider = ProfilingSamplerProvider(continuousSampleRate: 0, appLaunchSampleRate: 100)
        XCTAssertNil(provider.appLaunchProfilingSampled)

        provider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 100))
        XCTAssertEqual(provider.appLaunchProfilingSampled, true)

        provider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 0))
        XCTAssertEqual(provider.appLaunchProfilingSampled, false)

        let disabledProvider = ProfilingSamplerProvider(continuousSampleRate: 0, appLaunchSampleRate: 0)
        disabledProvider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 100))
        XCTAssertEqual(disabledProvider.appLaunchProfilingSampled, false)
    }

    func testInit_onlyAllowsAppLaunchSamplingWhenNativeProfilerStartedAtLaunch() {
        let configuration = Profiling.Configuration(applicationLaunchSampleRate: 100)
        let withoutNativeStart = ProfilerFeature(
            core: core,
            configuration: configuration,
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )
        XCTAssertFalse(withoutNativeStart.profilingSamplerProvider.isAppLaunchProfilingAvailable)

        dd_profiler_start_testing(100, false, Int64.max, 0)
        let withNativeStart = ProfilerFeature(
            core: core,
            configuration: configuration,
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )
        XCTAssertTrue(withNativeStart.profilingSamplerProvider.isAppLaunchProfilingAvailable)
    }

    func testProfilingSamplerProvider_hasNoMemoryProfilingDecision_withoutDeterministicSampler() {
        let provider = ProfilingSamplerProvider(continuousSampleRate: 0, memorySampleRate: 100)
        XCTAssertTrue(provider.isMemoryProfilingConfigured)
        XCTAssertFalse(provider.isContinuousProfilingConfigured)
        XCTAssertNil(provider.memoryProfilingSampled)
    }

    func testProfilingSamplerProvider_composesMemoryDecisionIndependentlyOfContinuous() {
        // Same RUM session: continuous configured out (0%), memory configured in (100%).
        let sessionSampler = DeterministicSampler(
            uuid: .mockWith("a1b2c3d4-e5f6-7890-abcd-d860b2b9437a"),
            samplingRate: 100
        )
        let provider = ProfilingSamplerProvider(continuousSampleRate: 0, memorySampleRate: 100)

        provider.updateWith(deterministicSampler: sessionSampler)

        XCTAssertEqual(provider.continuousProfilingSampled, false, "continuous 0% must sample out")
        XCTAssertEqual(provider.memoryProfilingSampled, true, "memory 100% must sample in — decisions are independent")
    }

    func testProfilingSamplerProvider_appliesChildRateCorrection() {
        // Given
        // seed 0xd860b2b9437a (~68.7% hash): NOT sampled at composed 40%, but sampled at profiling-only 80%.
        let sessionUUID = "a1b2c3d4-e5f6-7890-abcd-d860b2b9437a"
        let sessionSampleRate: SampleRate = 50
        let continuousSampleRate: SampleRate = 80
        let sessionSampler = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: sessionSampleRate)
        let expectedSampled = sessionSampler.combined(with: continuousSampleRate).isSampled
        let oldBehavior = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: continuousSampleRate).isSampled

        let provider = ProfilingSamplerProvider(continuousSampleRate: continuousSampleRate)

        // When
        provider.updateWith(deterministicSampler: sessionSampler)

        // Then
        XCTAssertNotEqual(expectedSampled, oldBehavior, "Chosen vector must differ between composed and profiling-only rate")
        XCTAssertEqual(provider.appLaunchProfilingSampled, false)
        XCTAssertEqual(provider.continuousProfilingSampled, expectedSampled)
    }

    func testMessageReceiver_updatesContinuousProfileSamplingWhenRUMContextChanges() {
        // Given
        let core = PassthroughCoreMock()
        let feature = ProfilerFeature(
            core: core,
            configuration: .init(continuousSampleRate: 100),
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        let unsampledContext: DatadogContext = .mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        let sampledContext: DatadogContext = .mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 100)]
        )

        // When
        _ = feature.messageReceiver.receive(message: .context(unsampledContext), from: core)

        // Then
        XCTAssertEqual(feature.profilingSamplerProvider.continuousProfilingSampled, false)

        // When
        _ = feature.messageReceiver.receive(message: .context(sampledContext), from: core)

        // Then
        XCTAssertEqual(feature.profilingSamplerProvider.continuousProfilingSampled, true)
    }

    func testMessageReceiver_keepsPreviousContinuousProfileSampling_whenContextHasNoRUM() {
        // Given
        let core = PassthroughCoreMock()
        let feature = ProfilerFeature(
            core: core,
            configuration: .init(continuousSampleRate: 100),
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            userDefaults: userDefaults
        )

        let unsampledContext: DatadogContext = .mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        let contextWithoutRUM: DatadogContext = .mockWith(additionalContext: [])

        // When
        _ = feature.messageReceiver.receive(message: .context(unsampledContext), from: core)

        // Then
        XCTAssertEqual(feature.profilingSamplerProvider.continuousProfilingSampled, false)

        // When
        _ = feature.messageReceiver.receive(message: .context(contextWithoutRUM), from: core)

        // Then
        XCTAssertEqual(feature.profilingSamplerProvider.continuousProfilingSampled, false)
    }
}

#endif // !os(watchOS)
