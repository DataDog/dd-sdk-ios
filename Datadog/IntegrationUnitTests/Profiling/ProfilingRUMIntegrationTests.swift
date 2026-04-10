/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if !os(watchOS)

import DatadogInternal
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports
import TestUtilities

@testable import DatadogProfiling
@testable import DatadogRUM

final class ProfilingRUMIntegrationTests: XCTestCase {
    private enum Fixtures {
        static let deterministicSessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        static let viewKey = "test-view"
        static let viewName = "Test View"
        static let customVitalName = "checkout"
        static let customVitalKey = "checkout-step"
        static let sampledInSessionRate: SampleRate = 60
        static let unsampledSessionRate: SampleRate = 50
        static let continuousSessionRate: SampleRate = 80
        static let continuousSampledInRate: SampleRate = 70
        static let continuousSampledOutRate: SampleRate = 50
        static let noEventTimeout: TimeInterval = 0.5
        static let eventTimeout: TimeInterval = 2
        static let profilerWarmup: TimeInterval = 0.1
        static let sampledProfileWarmup: TimeInterval = 2
        static let contextPropagationDelay: TimeInterval = 0.05
    }

    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        dd_profiler_stop()
        dd_profiler_start()

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
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()

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

        XCTAssertTrue(dd_is_profiling_enabled())
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

        let attachments = try XCTUnwrap(core.waitAndReturnEventsMetadata(ofFeature: ProfilerFeature.name, ofType: ProfileAttachments.self))
        XCTAssertEqual(attachments.count, 1)
        XCTAssertNotNil(attachments.first?.pprof)
        XCTAssertNotNil(attachments.first?.rumEvents)

        let profilingEvents = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: ProfilerFeature.name, ofType: ProfileEvent.self))
        XCTAssertEqual(profilingEvents.count, 1)
        let profilingEvent = try XCTUnwrap(profilingEvents.first)
        XCTAssertEqual(profilingEvent.family, "ios")
        XCTAssertEqual(profilingEvent.runtime, "ios")
        XCTAssertEqual(profilingEvent.attachments, [
            ProfileAttachments.Constants.wallFilename,
            ProfileAttachments.Constants.rumEventsFilename
        ])
        XCTAssertFalse(profilingEvent.tags.isEmpty)
        XCTAssertFalse(profilingEvent.additionalAttributes!.isEmpty)

        XCTAssertTrue(dd_is_profiling_enabled())
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

        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testContinuousProfilingWithoutRUM_itDoesNotSendAProfileEvent() {
        // When
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: .maxSampleRate)
        triggerProfileFlush()

        // Then
        XCTAssertTrue(profileEvents(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
        XCTAssertTrue(profileAttachments(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
    }

    func testCustomProfilingWithoutRUM_itDoesNotSendAProfileEvent() {
        // When
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0)
        triggerProfileFlush()

        // Then
        XCTAssertTrue(profileEvents(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
        XCTAssertTrue(profileAttachments(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
    }

    func testContinuousProfilingWithSampledInRUMSession_itSamplesContinuousProfilingIn() throws {
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.continuousSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 80%")
        try XCTSkipUnless(
            sessionSampler.combined(with: Fixtures.continuousSampledInRate).isSampled,
            "Precondition: UUID must be sampled at the combined 56% rate"
        )

        enableRUM(sessionSampleRate: Fixtures.continuousSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: Fixtures.continuousSampledInRate)

        startRUMView()
        waitForSampledRUMViewEvent()
        waitUntilContinuousProfilingSampled(true)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
    }

    func testContinuousProfilingWithSampledOutRUMSession_itDoesNotSendAProfileEvent() throws {
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.continuousSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 80%")
        try XCTSkipUnless(
            !sessionSampler.combined(with: Fixtures.continuousSampledOutRate).isSampled,
            "Precondition: UUID must NOT be sampled at the combined 40% rate"
        )

        enableRUM(sessionSampleRate: Fixtures.continuousSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: Fixtures.continuousSampledOutRate)

        startRUMView()
        waitForSampledRUMViewEvent()
        waitUntilContinuousProfilingSampled(false)
        triggerProfileFlush()
        XCTAssertTrue(profileEvents(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
        XCTAssertTrue(profileAttachments(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
    }

    func testCustomProfilingWithSampledInRUMSession_itDoesNotWriteProfileBeforeAVitalStarts() throws {
        let sessionUUID = Fixtures.deterministicSessionUUID
        try XCTSkipUnless(
            DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInSessionRate).isSampled,
            "Precondition: UUID must be sampled at 60%"
        )

        enableRUM(sessionSampleRate: Fixtures.sampledInSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0)

        startRUMView()
        waitForSampledRUMViewEvent()
        XCTAssertTrue(profileEvents(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
    }

    func testCustomProfilingWithSampledOutRUMSession_itDoesNotSendAProfileEvent() throws {
        let sessionUUID = Fixtures.deterministicSessionUUID
        try XCTSkipUnless(
            !DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.unsampledSessionRate).isSampled,
            "Precondition: UUID must NOT be sampled at 50%"
        )

        enableRUM(sessionSampleRate: Fixtures.unsampledSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0)

        startRUMView()
        startCustomVital()
        finishCustomVital()
        triggerProfileFlush()

        let rumViews = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMViewEvent.self,
            timeout: timeout(after: Fixtures.noEventTimeout)
        )
        XCTAssertTrue(rumViews.isEmpty)
        XCTAssertTrue(profileEvents(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
        XCTAssertTrue(profileAttachments(timeout: timeout(after: Fixtures.noEventTimeout)).isEmpty)
    }

    func testContinuousProfilingSamplesOut_customVitalStillSendsProfileEvent() throws {
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.continuousSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 80%")
        try XCTSkipUnless(
            !sessionSampler.combined(with: Fixtures.continuousSampledOutRate).isSampled,
            "Precondition: UUID must NOT be sampled at the combined 40% rate"
        )

        enableRUM(sessionSampleRate: Fixtures.continuousSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: Fixtures.continuousSampledOutRate)

        startRUMView()
        waitForSampledRUMViewEvent()
        waitUntilContinuousProfilingSampled(false)
        startCustomVital()
        finishCustomVital()
        triggerProfileFlush(after: Fixtures.sampledProfileWarmup)

        let attachments = try XCTUnwrap(profileAttachments(timeout: timeout(after: Fixtures.eventTimeout)).last)
        let rumVitals = try rumVitals(from: attachments)
        XCTAssertEqual(rumVitals.count, 1)
        XCTAssertEqual(rumVitals.first?["name"] as? String, Fixtures.customVitalName)
    }
}

private extension ProfilingRUMIntegrationTests {
    func enableRUM(sessionSampleRate: SampleRate, sessionUUID: UUID) {
        var configuration = RUM.Configuration(applicationID: "test-app-id")
        configuration.sessionSampleRate = sessionSampleRate
        configuration.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        configuration.frameInfoProviderFactory = {
            FrameInfoProviderMock(target: $0, selector: $1)
        }

        RUM.enable(with: configuration, in: core)
    }

    func enableProfiling(applicationLaunchSampleRate: SampleRate, continuousSampleRate: SampleRate) {
        Profiling.enable(
            with: .init(
                applicationLaunchSampleRate: applicationLaunchSampleRate,
                continuousSampleRate: continuousSampleRate
            ),
            in: core
        )
    }

    func startRUMView() {
        RUMMonitor.shared(in: core).startView(key: Fixtures.viewKey, name: Fixtures.viewName)
        core.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(Fixtures.contextPropagationDelay))
    }

    func startCustomVital() {
        RUMMonitor.shared(in: core).startFeatureOperation(
            name: Fixtures.customVitalName,
            operationKey: Fixtures.customVitalKey
        )
        core.flush()
    }

    func finishCustomVital() {
        RUMMonitor.shared(in: core).succeedFeatureOperation(
            name: Fixtures.customVitalName,
            operationKey: Fixtures.customVitalKey
        )
        core.flush()
    }

    func triggerProfileFlush(after warmup: TimeInterval = Fixtures.profilerWarmup) {
        RunLoop.main.run(until: Date().addingTimeInterval(warmup))
        NotificationCenter.default.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(Fixtures.contextPropagationDelay))
        core.flush()
    }

    func timeout(after interval: TimeInterval) -> DispatchTime {
        .now() + interval
    }

    func profileEvents(timeout: DispatchTime) -> [ProfileEvent] {
        core.waitAndReturnEvents(ofFeature: ProfilerFeature.name, ofType: ProfileEvent.self, timeout: timeout)
    }

    func profileAttachments(timeout: DispatchTime) -> [ProfileAttachments] {
        core.waitAndReturnEventsMetadata(ofFeature: ProfilerFeature.name, ofType: ProfileAttachments.self, timeout: timeout)
    }

    func rumVitals(from attachments: ProfileAttachments) throws -> [[String: Any]] {
        let rumEventsData = try XCTUnwrap(attachments.rumEvents)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [String: Any])
        return try XCTUnwrap(json["vitals"] as? [[String: Any]])
    }

    func waitForSampledRUMViewEvent() {
        let rumViews = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMViewEvent.self,
            timeout: timeout(after: Fixtures.eventTimeout)
        )
        XCTAssertFalse(rumViews.isEmpty)
    }

    func waitUntilContinuousProfilingSampled(_ expected: Bool) {
        let expectation = expectation(description: "continuous profiling sampled is \(expected)")
        wait(until: {
            self.core
                .feature(named: ProfilerFeature.name, type: ProfilerFeature.self)?
                .profilingSamplerProvider
                .continuousProfilingSampled == expected
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: Fixtures.eventTimeout + 0.5)
    }
}

#endif
