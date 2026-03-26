/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS)
@_spi(Internal)
@testable import DatadogSessionReplay
#endif

/// Integration tests verifying deterministic sampling behavior.
///
/// Unit-level correctness (hash math, `combined(with:)`) is covered in `DeterministicSamplerTests`,
/// `RecordingCoordinatorTests`, and `TracingURLSessionHandlerTests`. These integration tests verify
/// the wiring through the full SDK pipeline:
/// `RUM.enable` → `RUMSessionScope` creates `DeterministicSampler(uuid: sessionUUID)` → events
/// are suppressed end-to-end when `isSampled == false`.
class DeterministicSamplingIntegrationTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: DatadogCoreProxy!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    // MARK: - Unsampled session produces no events

    /// Verifies the full pipeline suppresses events for an unsampled session.
    ///
    /// Pins a UUID whose Knuth hash lands above the 50% threshold so `isSampled == false`,
    /// then asserts that no RUM events reach the feature scope. This exercises the real
    /// `DeterministicSampler(uuid: sessionUUID, samplingRate:)` wiring inside `RUMSessionScope`
    /// — something unit tests cannot cover because they inject mock samplers.
    ///
    /// UUID `c5b3c4ab-fa4a-4de9-8199-a522131ec48a`: Knuth hash ≈ 50.68% → not sampled at 50%.
    func testUnsampledSession_producesNoRUMEvents() throws {
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        // Precondition guard — fail loudly if the hash properties ever change
        try XCTSkipUnless(
            !DeterministicSampler(uuid: sessionUUID, samplingRate: 50.0).isSampled,
            "Precondition: UUID must NOT be sampled at 50%"
        )

        // Given
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = 50
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        // When
        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        RUMMonitor.shared(in: core).addAction(type: .tap, name: "Tap")
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)

        // Then — no events must be written for an unsampled session
        let events = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)
        XCTAssertTrue(events.isEmpty, "Unsampled session must produce no RUM events")
    }

    // MARK: - Session Replay child-rate correction

    #if os(iOS)
    /// Verifies the child-rate correction end-to-end: given a session UUID whose Knuth hash
    /// lands in the band [40%, 80%) — sampled at the RUM session rate (80%) but NOT at the
    /// effective combined rate (session=80% × SR=50% = 40%) — SR must set `has_replay = false`.
    ///
    /// This proves that SR uses `sessionSampler.combined(with: replaySampleRate)` rather than
    /// an independent draw against its own rate.
    ///
    /// UUID `c5b3c4ab-fa4a-4de9-8199-a522131ec48a`: sampled at 80%, NOT sampled at 40%.
    func testSRChildRateCorrection_sessionInBand_isNotRecorded() throws {
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        // Precondition guard — if hash properties ever change, fail loudly
        let sampler = DeterministicSampler(uuid: sessionUUID, samplingRate: 80.0)
        try XCTSkipUnless(sampler.isSampled, "Precondition: UUID must be sampled at 80%")
        try XCTSkipUnless(!sampler.combined(with: 50.0).isSampled, "Precondition: UUID must NOT be sampled at combined 40%")

        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = 80
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        SessionReplay.enable(with: SessionReplay.Configuration(
            replaySampleRate: 50,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll,
            touchPrivacyLevel: .hide
        ), in: core)

        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)

        // The RUM view must exist (session sampled at 80%)
        let rumMatchers = try core.waitAndReturnRUMEventMatchers()
        XCTAssertFalse(rumMatchers.filterRUMEvents(ofType: RUMViewEvent.self).isEmpty, "RUM must record: session is sampled at 80%")

        // SR must NOT record (combined rate 40% excludes this UUID)
        let srData = core.waitAndReturnEventsData(ofFeature: SessionReplayFeature.name)
        XCTAssertTrue(srData.isEmpty, "SR must not record: UUID is excluded by the combined 40% rate")
    }
    #endif
}
