/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogSessionReplay

class DDSessionReplayTests: XCTestCase {
    func testDefaultConfiguration() {
        // Given
        let sampleRate: Float = .mockRandom(min: 0, max: 100)

        // When
        let config = DDSessionReplayConfiguration(replaySampleRate: sampleRate)

        // Then
        XCTAssertEqual(config._swift.replaySampleRate, sampleRate)
        XCTAssertEqual(config._swift.defaultPrivacyLevel, .mask)
        XCTAssertEqual(config._swift.textAndInputPrivacyLevel, .maskAll)
        XCTAssertEqual(config._swift.imagePrivacyLevel, .maskAll)
        XCTAssertEqual(config._swift.touchPrivacyLevel, .hide)
        XCTAssertNil(config._swift.customEndpoint)
    }

    func testConfigurationWithNewApi() {
        // Given
        let textAndInputPrivacy: DDTextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let touchPrivacy: DDTouchPrivacyLevel = [.show, .hide].randomElement()!
        let imagePrivacy: DDImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let sampleRate: Float = .mockRandom(min: 0, max: 100)

        // When
        let config = DDSessionReplayConfiguration(
            replaySampleRate: sampleRate,
            textAndInputPrivacyLevel: textAndInputPrivacy,
            imagePrivacyLevel: imagePrivacy,
            touchPrivacyLevel: touchPrivacy
        )

        // Then
        XCTAssertEqual(config._swift.replaySampleRate, sampleRate)
        XCTAssertEqual(config._swift.textAndInputPrivacyLevel, textAndInputPrivacy._swift)
        XCTAssertEqual(config._swift.imagePrivacyLevel, imagePrivacy._swift)
        XCTAssertEqual(config._swift.touchPrivacyLevel, touchPrivacy._swift)
        XCTAssertNil(config._swift.customEndpoint)
    }

    func testConfigurationOverrides() {
        // Given
        let sampleRate: Float = .mockRandom(min: 0, max: 100)
        let privacy: DDSessionReplayConfigurationPrivacyLevel = [.allow, .mask, .maskUserInput].randomElement()!
        let textAndInputPrivacy: DDTextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: DDImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: DDTouchPrivacyLevel = [.show, .hide].randomElement()!
        let url: URL = .mockRandom()

        // When
        let config = DDSessionReplayConfiguration(replaySampleRate: 100)
        config.replaySampleRate = sampleRate
        config.defaultPrivacyLevel = privacy
        config.textAndInputPrivacyLevel = textAndInputPrivacy
        config.imagePrivacyLevel = imagePrivacy
        config.touchPrivacyLevel = touchPrivacy
        config.customEndpoint = url

        // Then
        XCTAssertEqual(config._swift.replaySampleRate, sampleRate)
        XCTAssertEqual(config._swift.defaultPrivacyLevel, privacy._swift)
        XCTAssertEqual(config._swift.textAndInputPrivacyLevel, textAndInputPrivacy._swift)
        XCTAssertEqual(config._swift.imagePrivacyLevel, imagePrivacy._swift)
        XCTAssertEqual(config._swift.touchPrivacyLevel, touchPrivacy._swift)
        XCTAssertEqual(config._swift.customEndpoint, url)
    }

    func testConfigurationOverridesWithNewApi() {
        // Given
        let sampleRate: Float = .mockRandom(min: 0, max: 100)
        let textAndInputPrivacy: DDTextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: DDImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: DDTouchPrivacyLevel = [.show, .hide].randomElement()!
        let url: URL = .mockRandom()

        // When
        let config = DDSessionReplayConfiguration(
            replaySampleRate: 100,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll,
            touchPrivacyLevel: .hide
        )
        config.replaySampleRate = sampleRate
        config.textAndInputPrivacyLevel = textAndInputPrivacy
        config.imagePrivacyLevel = imagePrivacy
        config.touchPrivacyLevel = touchPrivacy
        config.customEndpoint = url

        // Then
        XCTAssertEqual(config._swift.replaySampleRate, sampleRate)
        XCTAssertEqual(config._swift.textAndInputPrivacyLevel, textAndInputPrivacy._swift)
        XCTAssertEqual(config._swift.imagePrivacyLevel, imagePrivacy._swift)
        XCTAssertEqual(config._swift.touchPrivacyLevel, touchPrivacy._swift)
        XCTAssertEqual(config._swift.customEndpoint, url)
    }

    func testPrivacyLevelsInterop() {
        XCTAssertEqual(DDSessionReplayConfigurationPrivacyLevel.allow._swift, .allow)
        XCTAssertEqual(DDSessionReplayConfigurationPrivacyLevel.mask._swift, .mask)
        XCTAssertEqual(DDSessionReplayConfigurationPrivacyLevel.maskUserInput._swift, .maskUserInput)

        XCTAssertEqual(DDSessionReplayConfigurationPrivacyLevel(.allow), .allow)
        XCTAssertEqual(DDSessionReplayConfigurationPrivacyLevel(.mask), .mask)
        XCTAssertEqual(DDSessionReplayConfigurationPrivacyLevel(.maskUserInput), .maskUserInput)
    }

    func testTextAndInputPrivacyLevelsInterop() {
        XCTAssertEqual(DDTextAndInputPrivacyLevel.maskAll._swift, .maskAll)
        XCTAssertEqual(DDTextAndInputPrivacyLevel.maskAllInputs._swift, .maskAllInputs)
        XCTAssertEqual(DDTextAndInputPrivacyLevel.maskSensitiveInputs._swift, .maskSensitiveInputs)

        XCTAssertEqual(DDTextAndInputPrivacyLevel(.maskAll), .maskAll)
        XCTAssertEqual(DDTextAndInputPrivacyLevel(.maskAllInputs), .maskAllInputs)
        XCTAssertEqual(DDTextAndInputPrivacyLevel(.maskSensitiveInputs), .maskSensitiveInputs)
    }

    func testImagePrivacyLevelsInterop() {
        XCTAssertEqual(DDImagePrivacyLevel.maskAll._swift, .maskAll)
        XCTAssertEqual(DDImagePrivacyLevel.maskNonBundledOnly._swift, .maskNonBundledOnly)
        XCTAssertEqual(DDImagePrivacyLevel.maskNone._swift, .maskNone)

        XCTAssertEqual(DDImagePrivacyLevel(.maskAll), .maskAll)
        XCTAssertEqual(DDImagePrivacyLevel(.maskNonBundledOnly), .maskNonBundledOnly)
        XCTAssertEqual(DDImagePrivacyLevel(.maskNone), .maskNone)
    }

    func testTouchPrivacyLevelsInterop() {
        XCTAssertEqual(DDTouchPrivacyLevel.show._swift, .show)
        XCTAssertEqual(DDTouchPrivacyLevel.hide._swift, .hide)

        XCTAssertEqual(DDTouchPrivacyLevel(.show), .show)
        XCTAssertEqual(DDTouchPrivacyLevel(.hide), .hide)
    }

    func testWhenEnabled() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        let config = DDSessionReplayConfiguration(replaySampleRate: 42)

        // When
        DDSessionReplay.enable(with: config)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        let requestBuilder = try XCTUnwrap(sr.requestBuilder as? DatadogSessionReplay.SegmentRequestBuilder)
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 42)
        XCTAssertEqual(sr.recordingCoordinator.textAndInputPrivacy, .maskAll)
        XCTAssertEqual(sr.recordingCoordinator.imagePrivacy, .maskAll)
        XCTAssertEqual(sr.recordingCoordinator.touchPrivacy, .hide)
        XCTAssertNil(requestBuilder.customUploadURL)
    }

    func testWhenEnabledWithNewApi() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)
        let textAndInputPrivacy: DDTextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: DDImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: DDTouchPrivacyLevel = [.show, .hide].randomElement()!
        defer { CoreRegistry.unregisterDefault() }

        let config = DDSessionReplayConfiguration(
            replaySampleRate: 42,
            textAndInputPrivacyLevel: textAndInputPrivacy,
            imagePrivacyLevel: imagePrivacy,
            touchPrivacyLevel: touchPrivacy
        )

        // When
        DDSessionReplay.enable(with: config)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        let requestBuilder = try XCTUnwrap(sr.requestBuilder as? DatadogSessionReplay.SegmentRequestBuilder)
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 42)
        XCTAssertEqual(sr.recordingCoordinator.textAndInputPrivacy, textAndInputPrivacy._swift)
        XCTAssertEqual(sr.recordingCoordinator.imagePrivacy, imagePrivacy._swift)
        XCTAssertEqual(sr.recordingCoordinator.touchPrivacy, touchPrivacy._swift)
        XCTAssertNil(requestBuilder.customUploadURL)
    }
}
#endif
