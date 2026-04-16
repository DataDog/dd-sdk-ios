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
        static let sampledInRUMSessionRate: SampleRate = 60
        static let unsampledRUMSessionRate: SampleRate = 50
        static let continuousSampledInRate: SampleRate = 85
        static let continuousSampledOutRate: SampleRate = 50
        static let minProfileDuration: TimeInterval = 0.1
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

    func testProfilingWithoutRUM_itDoesNotSendAProfileEvent() {
        // When
        enableProfiling()

        // Then
        // No passive output should be produced when profiling is enabled without RUM.
        assertNoProfileOutput()

        // No output should be produced even after forcing a profile flush.
        triggerProfileFlush()
        assertNoProfileOutput(timeout: timeout(after: 1.0))
        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testWhenRUMSendsTTIDMessage_itSendsAProfileEvent() throws {
        var frameInfoProvider: FrameInfoProviderMock? = nil

        // When
        enableRUM(
            sessionSampleRate: .maxSampleRate,
            sessionUUID: Fixtures.deterministicSessionUUID,
            frameInfoProviderFactory: {
                frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
                return frameInfoProvider!
            }
        )
        enableProfiling()
        startRUMView()

        frameInfoProvider?.triggerCallback(interval: 1)

        // Then
        waitAndAssertRUMViewEvents()
        waitAndAssertRUMAppLaunchVitalEvents(count: 1)
        try waitAndAssertProfileOutput(count: 1)

        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testWhenRUMDoesNotSendTTIDMessage_itDoesNotSendAProfileEvent() throws {
        var frameInfoProvider: FrameInfoProviderMock? = nil

        // When
        enableRUM(
            sessionSampleRate: .maxSampleRate,
            sessionUUID: Fixtures.deterministicSessionUUID,
            frameInfoProviderFactory: {
                frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
                return frameInfoProvider!
            }
        )
        enableProfiling()
        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitAndAssertRUMAppLaunchVitalEvents(count: 0)
        try waitAndAssertProfileOutput(count: 0)

        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testContinuousProfilingWithSampledInRUMSession_itSamplesContinuousProfilingIn() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 60%")
        try XCTSkipUnless(
            sessionSampler.combined(with: Fixtures.continuousSampledInRate).isSampled,
            "Precondition: UUID must be sampled at the combined 51% rate"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(continuousSampleRate: Fixtures.continuousSampledInRate)

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitUntilContinuousProfilingSampled(true)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
    }

    func testContinuousProfilingWithSampledOutRUMSession_itDoesNotSendAProfileEvent() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 60%")
        try XCTSkipUnless(
            !sessionSampler.combined(with: Fixtures.continuousSampledOutRate).isSampled,
            "Precondition: UUID must NOT be sampled at the combined 30% rate"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(continuousSampleRate: Fixtures.continuousSampledOutRate)

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitUntilContinuousProfilingSampled(false)
        triggerProfileFlush()
        assertNoProfileOutput(timeout: timeout(after: 0.1))
    }

    func testCustomProfilingWithSampledInRUMSession_itDoesNotWriteProfileBeforeAVitalStarts() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        try XCTSkipUnless(
            DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate).isSampled,
            "Precondition: UUID must be sampled at 60%"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0) // custom profiling

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        assertNoProfileOutput(timeout: timeout(after: 0.5))
    }

    func testCustomProfilingWithSampledOutRUMSession_itDoesNotSendAProfileEvent() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let vitalName = "vital-name"
        try XCTSkipUnless(
            !DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.unsampledRUMSessionRate).isSampled,
            "Precondition: UUID must NOT be sampled at 50%"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.unsampledRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0) // custom profiling

        startRUMView()
        startVital(name: vitalName)
        finishVital(name: vitalName)

        // Then
        triggerProfileFlush()

        let rumViews = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMViewEvent.self,
            timeout: timeout(after: 0.1)
        )
        XCTAssertTrue(rumViews.isEmpty)
        assertNoProfileOutput(timeout: timeout(after: 0.1))
    }

    func testContinuousProfilingSamplesOut_customVitalStillSendsProfileEvent() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let vitalName = "vital-name"
        let operationKey = "vital-key"
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 60%")
        try XCTSkipUnless(
            !sessionSampler.combined(with: Fixtures.continuousSampledOutRate).isSampled,
            "Precondition: UUID must NOT be sampled at the combined 30% rate"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(continuousSampleRate: Fixtures.continuousSampledOutRate)

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitUntilContinuousProfilingSampled(false)
        waitUntilProfilerStatus(DD_PROFILER_STATUS_STOPPED, description: "continuous profiling is stopped")

        startVital(name: vitalName, operationKey: operationKey)
        waitUntilProfilerStatus(DD_PROFILER_STATUS_RUNNING, description: "profiler is running for the custom vital")

        finishVital(name: vitalName, operationKey: operationKey)
        waitUntilProfilerStatus(DD_PROFILER_STATUS_STOPPED, description: "profiler is stopped after the custom vital")

        let attachments = try XCTUnwrap(waitForProfileAttachments().last)
        let rumVitals = try rumVitals(from: attachments)
        XCTAssertEqual(rumVitals.count, 1)
        XCTAssertEqual(rumVitals.first?["name"] as? String, vitalName)
    }
}

private extension ProfilingRUMIntegrationTests {
    func enableRUM(
        sessionSampleRate: SampleRate,
        sessionUUID: UUID,
        dateProvider: DateProvider = DateProviderMock(),
        mediaTimeProvider: CACurrentMediaTimeProvider = MediaTimeProviderMock(current: 0),
        frameInfoProviderFactory: ((Any, Selector) -> FrameInfoProvider)? = nil
    ) {
        var configuration = RUM.Configuration(applicationID: "test-app-id")
        configuration.sessionSampleRate = sessionSampleRate
        configuration.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        configuration.dateProvider = dateProvider
        configuration.mediaTimeProvider = mediaTimeProvider
        configuration.frameInfoProviderFactory = frameInfoProviderFactory ?? {
            FrameInfoProviderMock(target: $0, selector: $1)
        }

        RUM.enable(with: configuration, in: core)
    }

    func enableProfiling(applicationLaunchSampleRate: SampleRate = .maxSampleRate, continuousSampleRate: SampleRate = .maxSampleRate) {
        var configuration = Profiling.Configuration(
            applicationLaunchSampleRate: applicationLaunchSampleRate,
            continuousSampleRate: continuousSampleRate
        )
        configuration.minProfileDuration = Fixtures.minProfileDuration

        Profiling.enable(
            with: configuration,
            in: core
        )
    }

    func startRUMView() {
        RUMMonitor.shared(in: core).startView(key: "test-view", name: "Test View")
    }

    func startVital(name: String, operationKey: String? = nil) {
        RUMMonitor.shared(in: core).startOperation(
            name: name,
            operationKey: operationKey,
            options: ProfilingOptions(sampleRate: .maxSampleRate)
        )
    }

    func finishVital(name: String, operationKey: String? = nil) {
        RUMMonitor.shared(in: core).succeedOperation(
            name: name,
            operationKey: operationKey
        )
    }

    func triggerProfileFlush() {
        let expectation = expectation(description: "read latest profiler context")
        var currentContext: DatadogContext?
        core.scope(for: ProfilerFeature.self).context {
            currentContext = $0
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        guard var backgroundContext = currentContext else {
            XCTFail("Expected to read the latest profiler context before triggering a background flush")
            return
        }
        backgroundContext.applicationStateHistory.append(state: .background, at: Date())
        core.context = backgroundContext
        core.send(message: .context(backgroundContext), else: {})
        // Wait until all the pieces injected in the context and shared between modules are in place.
        core.flush()
    }

    func timeout(after interval: TimeInterval) -> DispatchTime {
        .now() + interval
    }

    func rumVitals(from attachments: ProfileAttachments) throws -> [[String: Any]] {
        let rumEventsData = try XCTUnwrap(attachments.rumEvents)
        let rumEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [[String: Any]])
        return rumEvents.filter { $0["type"] as? String == "vital" }
    }

    func waitAndAssertRUMViewEvents(expectedViewName: String = "Test View") {
        let rumViews = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMViewEvent.self,
            timeout: timeout(after: 1.0)
        )

        XCTAssertFalse(rumViews.isEmpty)
        XCTAssertTrue(rumViews.allSatisfy { $0.type == "view" })
        XCTAssertTrue(rumViews.contains { $0.view.name == "ApplicationLaunch" })
        XCTAssertTrue(rumViews.contains { $0.view.name == expectedViewName })

        let matchingView = rumViews.last { $0.view.name == expectedViewName }
        XCTAssertTrue(matchingView.map { $0.view.id.isEmpty == false } ?? false)
    }

    func waitAndAssertRUMAppLaunchVitalEvents(count expectedCount: Int) {
        let rumVitalEvents = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMVitalAppLaunchEvent.self,
            timeout: timeout(after: 1.0)
        )

        XCTAssertEqual(rumVitalEvents.count, expectedCount)

        if let ttidVitalEvent = rumVitalEvents.first {
            XCTAssertEqual(ttidVitalEvent.dd.profiling?.status, .running)
            XCTAssertEqual(ttidVitalEvent.vital.appLaunchMetric, .ttid)
        }
    }

    func waitAndAssertProfileOutput(count expectedCount: Int) throws {
        let attachments = try XCTUnwrap(core.waitAndReturnEventsMetadata(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileAttachments.self
        ))

        XCTAssertEqual(attachments.count, expectedCount)

        if let attachment = attachments.first {
            XCTAssertNotNil(attachment.pprof)
            XCTAssertNotNil(attachment.rumEvents)
        }

        let profilingEvents = try XCTUnwrap(core.waitAndReturnEvents(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileEvent.self
        ))
        XCTAssertEqual(profilingEvents.count, expectedCount)

        if let profilingEvent = profilingEvents.first {
            XCTAssertEqual(profilingEvent.family, "ios")
            XCTAssertEqual(profilingEvent.runtime, "ios")
            XCTAssertEqual(profilingEvent.attachments, [
                ProfileAttachments.Constants.wallFilename,
                ProfileAttachments.Constants.rumEventsFilename
            ])
            XCTAssertFalse(profilingEvent.tags.isEmpty)
            XCTAssertFalse(profilingEvent.additionalAttributes!.isEmpty)
        }
    }

    func assertNoProfileOutput(timeout: DispatchTime = .now() + 0.1) {
        XCTAssertTrue(core.waitAndReturnEvents(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileEvent.self,
            timeout: timeout
        ).isEmpty)
        XCTAssertTrue(core.waitAndReturnEventsMetadata(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileAttachments.self,
            timeout: timeout
        ).isEmpty)
    }

    func waitForProfileAttachments(timeout: TimeInterval = 1.0) -> [ProfileAttachments] {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            core.flush()
            let attachments = core.waitAndReturnEventsMetadata(
                ofFeature: ProfilerFeature.name,
                ofType: ProfileAttachments.self,
                timeout: .now()
            )
            if attachments.isEmpty == false {
                return attachments
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                wait(during: min(0.05, remaining)) {}
            }
        } while Date() < deadline

        return []
    }

    func waitUntilContinuousProfilingSampled(_ expected: Bool) {
        let expectation = expectation(description: "continuous profiling sampled is \(expected)")
        wait(until: {
            self.core.flush()
            return self.core
                .feature(named: ProfilerFeature.name, type: ProfilerFeature.self)?
                .profilingSamplerProvider
                .continuousProfilingSampled == expected
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 1.0)
    }

    func waitUntilProfilerStatus(_ expected: dd_profiler_status_t, description: String) {
        let expectation = expectation(description: description)
        wait(until: {
            dd_profiler_get_status() == expected
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 1.0)
    }
}

#endif
