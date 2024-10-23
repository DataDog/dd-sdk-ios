/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogSessionReplay

class DDSessionReplayTests: XCTestCase {
    func testDefaultConfiguration() {
        // Given
        let sampleRate: Float = .mockRandom(min: 0, max: 100)

        // When
        let config = objc_SessionReplayConfiguration(replaySampleRate: sampleRate)

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
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let touchPrivacy: objc_TouchPrivacyLevel = [.show, .hide].randomElement()!
        let imagePrivacy: objc_ImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let sampleRate: Float = .mockRandom(min: 0, max: 100)

        // When
        let config = objc_SessionReplayConfiguration(
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
        let privacy: objc_SessionReplayConfigurationPrivacyLevel = [.allow, .mask, .maskUserInput].randomElement()!
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: objc_ImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: objc_TouchPrivacyLevel = [.show, .hide].randomElement()!
        let url: URL = .mockRandom()

        // When
        let config = objc_SessionReplayConfiguration(replaySampleRate: 100)
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
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: objc_ImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: objc_TouchPrivacyLevel = [.show, .hide].randomElement()!
        let url: URL = .mockRandom()

        // When
        let config = objc_SessionReplayConfiguration(
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
        XCTAssertEqual(objc_SessionReplayConfigurationPrivacyLevel.allow._swift, .allow)
        XCTAssertEqual(objc_SessionReplayConfigurationPrivacyLevel.mask._swift, .mask)
        XCTAssertEqual(objc_SessionReplayConfigurationPrivacyLevel.maskUserInput._swift, .maskUserInput)

        XCTAssertEqual(objc_SessionReplayConfigurationPrivacyLevel(.allow), .allow)
        XCTAssertEqual(objc_SessionReplayConfigurationPrivacyLevel(.mask), .mask)
        XCTAssertEqual(objc_SessionReplayConfigurationPrivacyLevel(.maskUserInput), .maskUserInput)
    }

    func testTextAndInputPrivacyLevelsInterop() {
        XCTAssertEqual(objc_TextAndInputPrivacyLevel.maskAll._swift, .maskAll)
        XCTAssertEqual(objc_TextAndInputPrivacyLevel.maskAllInputs._swift, .maskAllInputs)
        XCTAssertEqual(objc_TextAndInputPrivacyLevel.maskSensitiveInputs._swift, .maskSensitiveInputs)

        XCTAssertEqual(objc_TextAndInputPrivacyLevel(.maskAll), .maskAll)
        XCTAssertEqual(objc_TextAndInputPrivacyLevel(.maskAllInputs), .maskAllInputs)
        XCTAssertEqual(objc_TextAndInputPrivacyLevel(.maskSensitiveInputs), .maskSensitiveInputs)
    }

    func testImagePrivacyLevelsInterop() {
        XCTAssertEqual(objc_ImagePrivacyLevel.maskAll._swift, .maskAll)
        XCTAssertEqual(objc_ImagePrivacyLevel.maskNonBundledOnly._swift, .maskNonBundledOnly)
        XCTAssertEqual(objc_ImagePrivacyLevel.maskNone._swift, .maskNone)

        XCTAssertEqual(objc_ImagePrivacyLevel(.maskAll), .maskAll)
        XCTAssertEqual(objc_ImagePrivacyLevel(.maskNonBundledOnly), .maskNonBundledOnly)
        XCTAssertEqual(objc_ImagePrivacyLevel(.maskNone), .maskNone)
    }

    func testTouchPrivacyLevelsInterop() {
        XCTAssertEqual(objc_TouchPrivacyLevel.show._swift, .show)
        XCTAssertEqual(objc_TouchPrivacyLevel.hide._swift, .hide)

        XCTAssertEqual(objc_TouchPrivacyLevel(.show), .show)
        XCTAssertEqual(objc_TouchPrivacyLevel(.hide), .hide)
    }

    func testWhenEnabled() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        let config = objc_SessionReplayConfiguration(replaySampleRate: 42)

        // When
        objc_SessionReplay.enable(with: config)

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
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevel = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: objc_ImagePrivacyLevel = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: objc_TouchPrivacyLevel = [.show, .hide].randomElement()!
        defer { CoreRegistry.unregisterDefault() }

        let config = objc_SessionReplayConfiguration(
            replaySampleRate: 42,
            textAndInputPrivacyLevel: textAndInputPrivacy,
            imagePrivacyLevel: imagePrivacy,
            touchPrivacyLevel: touchPrivacy
        )

        // When
        objc_SessionReplay.enable(with: config)

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
