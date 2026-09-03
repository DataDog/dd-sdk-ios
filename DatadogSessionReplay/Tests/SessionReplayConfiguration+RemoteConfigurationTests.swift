/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogSessionReplay

class SessionReplayConfiguration_RemoteConfigurationTests: XCTestCase {
    /// When there is no remote configuration (`nil`) or its `sessionReplay` namespace is absent,
    /// Session Replay must behave exactly as configured in-code.
    func testWhenNoRemoteValuesAreProvided_itLeavesConfigurationUnchanged() {
        let baseline = SessionReplay.Configuration(
            replaySampleRate: 42,
            textAndInputPrivacyLevel: .maskSensitiveInputs,
            imagePrivacyLevel: .maskNone,
            touchPrivacyLevel: .show,
            startRecordingImmediately: false
        )

        var withNilRemote = baseline
        withNilRemote.apply(remoteConfiguration: nil)
        DDAssertReflectionEqual(withNilRemote, baseline)

        var withEmptyRemote = baseline
        withEmptyRemote.apply(remoteConfiguration: .mockWith()) // every namespace absent
        DDAssertReflectionEqual(withEmptyRemote, baseline)

        var withEmptyNamespace = baseline
        withEmptyNamespace.apply(remoteConfiguration: .mockWith(sessionReplay: .mockWith())) // all fields absent
        DDAssertReflectionEqual(withEmptyNamespace, baseline)
    }

    /// A fully-populated remote `sessionReplay` namespace must override every mapped behavioral
    /// parameter, regardless of the in-code baseline. Both the baseline and the remote are randomized
    /// and the check repeated, so random enum/boolean values exercise every branch over the run.
    func testItOverridesEveryBehavioralParameterFromRemoteValues() throws {
        for _ in 0..<100 {
            // Given
            let sessionReplay: RemoteConfiguration.SessionReplay = .mockRandom()
            var configuration = SessionReplay.Configuration(
                replaySampleRate: .mockRandom(min: 0, max: 100),
                textAndInputPrivacyLevel: [.maskSensitiveInputs, .maskAllInputs, .maskAll].randomElement()!,
                imagePrivacyLevel: [.maskNone, .maskNonBundledOnly, .maskAll].randomElement()!,
                touchPrivacyLevel: [.show, .hide].randomElement()!,
                startRecordingImmediately: .mockRandom()
            )

            // When
            configuration.apply(remoteConfiguration: .mockWith(sessionReplay: sessionReplay))

            // Then
            XCTAssertEqual(configuration.replaySampleRate, SampleRate(try XCTUnwrap(sessionReplay.sampleRate)))
            XCTAssertEqual(configuration.textAndInputPrivacyLevel, expectedTextAndInputPrivacy(try XCTUnwrap(sessionReplay.textAndInputPrivacy)))
            XCTAssertEqual(configuration.imagePrivacyLevel, expectedImagePrivacy(try XCTUnwrap(sessionReplay.imagePrivacy)))
            XCTAssertEqual(configuration.touchPrivacyLevel, expectedTouchPrivacy(try XCTUnwrap(sessionReplay.touchPrivacy)))
        }
    }

    /// A parameter the remote configuration omits must keep its in-code value while the present ones
    /// are overridden.
    func testWhenRemoteProvidesSomeValues_itKeepsInCodeValuesForTheOthers() {
        // Given
        var configuration = SessionReplay.Configuration(
            replaySampleRate: 10,
            textAndInputPrivacyLevel: .maskSensitiveInputs,
            imagePrivacyLevel: .maskNone,
            touchPrivacyLevel: .show,
            startRecordingImmediately: true
        )

        // When — only `sampleRate` and `touchPrivacy` are provided remotely
        configuration.apply(remoteConfiguration: .mockWith(sessionReplay: .mockWith(sampleRate: 90, touchPrivacy: .hide)))

        // Then — provided values overridden
        XCTAssertEqual(configuration.replaySampleRate, 90)
        XCTAssertEqual(configuration.touchPrivacyLevel, .hide)
        // Then — omitted values preserved
        XCTAssertEqual(configuration.textAndInputPrivacyLevel, .maskSensitiveInputs)
        XCTAssertEqual(configuration.imagePrivacyLevel, .maskNone)
        XCTAssertTrue(configuration.startRecordingImmediately)
    }

    // MARK: - Helpers

    private func expectedTextAndInputPrivacy(
        _ remote: RemoteConfiguration.SessionReplay.TextAndInputPrivacy
    ) -> TextAndInputPrivacyLevel {
        switch remote {
        case .maskSensitiveInputs: return .maskSensitiveInputs
        case .maskAllInputs: return .maskAllInputs
        case .maskAll: return .maskAll
        }
    }

    private func expectedImagePrivacy(
        _ remote: RemoteConfiguration.SessionReplay.ImagePrivacy
    ) -> ImagePrivacyLevel {
        switch remote {
        case .maskNone: return .maskNone
        case .maskNonBundledOnly: return .maskNonBundledOnly
        case .maskAll: return .maskAll
        }
    }

    private func expectedTouchPrivacy(
        _ remote: RemoteConfiguration.SessionReplay.TouchPrivacy
    ) -> TouchPrivacyLevel {
        switch remote {
        case .show: return .show
        case .hide: return .hide
        }
    }
}
#endif
