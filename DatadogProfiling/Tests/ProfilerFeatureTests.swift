/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogInternal
import DatadogMachProfiler
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
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testInit_setsIsEnabledFlagToTrue() {
        // Given
        XCTAssertNil(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY))

        // When
        _ = makeFeature()

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool, true)
    }

    func testInit_setsSampleRateValue() {
        // Given
        userDefaults.removeObject(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY)
        let newSampleRate: SampleRate = 23

        // When
        _ = makeFeature(configuration: .init(applicationLaunchSampleRate: newSampleRate))

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY) as? SampleRate, newSampleRate)
    }

    func testInit_overridesPreviousSampleRate_whenNewSampleRateIsLower() {
        // Given
        let previousSampleRate: SampleRate = 80
        let lowerSampleRate: SampleRate = 20

        userDefaults.setValue(previousSampleRate, forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY)
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY) as? SampleRate, previousSampleRate)

        // When
        _ = makeFeature(configuration: .init(applicationLaunchSampleRate: lowerSampleRate))

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY) as? SampleRate, lowerSampleRate)
    }

    func testInit_keepsPreviousSampleRate_whenNewSampleRateIsHigher() {
        // Given
        let previousSampleRate: SampleRate = 20
        let higherSampleRate: SampleRate = 80

        userDefaults.setValue(previousSampleRate, forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY)
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY) as? SampleRate, previousSampleRate)

        // When
        _ = makeFeature(configuration: .init(applicationLaunchSampleRate: higherSampleRate))

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY) as? SampleRate, previousSampleRate)
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

    func testProfilingSamplerProvider_hasNoContinuousProfilingDecision_withoutDeterministicSampler() {
        XCTAssertNil(ProfilingSamplerProvider(continuousSampleRate: 100).continuousProfilingSampled)
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
        XCTAssertEqual(provider.continuousProfilingSampled, expectedSampled)
    }

    func testMessageReceiver_updatesContinuousProfileSamplingWhenRUMContextChanges() {
        // Given
        let core = PassthroughCoreMock()
        let quotaChecker = ProfilingQuotaCheckerMock()
        let feature = makeFeature(
            core: core,
            configuration: .init(continuousSampleRate: 100),
            quotaChecker: quotaChecker
        )

        let unsampledContext: DatadogContext = .mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )
        let sessionID = UUID(uuidString: "abcdef01-2345-6789-abcd-ef0123456789")!
        let sampledContext: DatadogContext = .mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID, sessionSampleRate: 100)]
        )

        // When
        _ = feature.messageReceiver.receive(message: .context(unsampledContext), from: core)

        // Then
        XCTAssertEqual(feature.profilingSamplerProvider.continuousProfilingSampled, false)

        // When
        _ = feature.messageReceiver.receive(message: .context(sampledContext), from: core)

        // Then
        XCTAssertEqual(feature.profilingSamplerProvider.continuousProfilingSampled, true)
        XCTAssertEqual(
            quotaChecker.receivedContexts.compactMap { $0.additionalContext(ofType: RUMCoreContext.self)?.sessionID },
            [
                unsampledContext.additionalContext(ofType: RUMCoreContext.self)?.sessionID,
                sessionID.uuidString.lowercased()
            ]
        )
    }

    func testMessageReceiver_keepsPreviousContinuousProfileSampling_whenContextHasNoRUM() {
        // Given
        let core = PassthroughCoreMock()
        let feature = makeFeature(core: core, configuration: .init(continuousSampleRate: 100))

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

    func testMessageReceiver_requestsQuotaAsSoonAsContextChanges() {
        // Given
        let core = PassthroughCoreMock()
        let quotaChecker = ProfilingQuotaCheckerMock()
        let feature = makeFeature(
            core: core,
            configuration: .init(continuousSampleRate: 100),
            quotaChecker: quotaChecker
        )
        let context: DatadogContext = .mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 100)]
        )

        // When
        _ = feature.messageReceiver.receive(message: .context(context), from: core)
        _ = feature.messageReceiver.receive(message: .context(context), from: core)

        // Then
        XCTAssertEqual(quotaChecker.receivedContexts.count, 2)
    }

    private func makeFeature(
        core: DatadogCoreProtocol = PassthroughCoreMock(),
        configuration: Profiling.Configuration = .init(),
        quotaChecker: ProfilingQuotaChecking = ProfilingQuotaCheckerMock()
    ) -> ProfilerFeature {
        ProfilerFeature(
            core: core,
            configuration: configuration,
            requestBuilder: requestBuilder,
            telemetryController: telemetryController,
            quotaChecker: quotaChecker,
            userDefaults: userDefaults
        )
    }
}

#endif // !os(watchOS)
