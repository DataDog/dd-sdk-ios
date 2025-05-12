/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogSessionReplay

class SessionReplayTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: SessionReplay.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)
        config = SessionReplay.Configuration(replaySampleRate: 100)
    }

    override func tearDown() {
        core = nil
        config = nil
        CoreRegistry.unregisterDefault()
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
    }

    // MARK: - Initialization Tests

    func testWhenEnabled_itRegistersSessionReplayFeature() {
        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: SessionReplayFeature.self))
        XCTAssertNotNil(core.get(feature: ResourcesFeature.self))
    }

    func testWhenEnabledInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        SessionReplay.enable(with: config, in: NOPDatadogCore())

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `SessionReplay.enable(with:)`."
        )
    }

    func testWhenEnabledMultipleTimes_itPrintsError() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        SessionReplay.enable(with: config, in: core)
        SessionReplay.enable(with: config, in: core)

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Session Replay is already enabled and does not support multiple instances. The existing instance will continue to be used."
        )
    }

    // MARK: - Configuration Tests

    func testWhenEnabledWithDefaultConfiguration() throws {
        config = SessionReplay.Configuration(replaySampleRate: 42)

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 42)
        XCTAssertEqual(sr.recordingCoordinator.textAndInputPrivacy, .maskAll)
        XCTAssertEqual(sr.recordingCoordinator.imagePrivacy, .maskAll)
        XCTAssertEqual(sr.recordingCoordinator.touchPrivacy, .hide)
        XCTAssertNil((sr.requestBuilder as? SegmentRequestBuilder)?.customUploadURL)
        let r = try XCTUnwrap(core.get(feature: ResourcesFeature.self))
        XCTAssertNil((r.requestBuilder as? ResourceRequestBuilder)?.customUploadURL)
    }

    func testWhenEnabledWithNewAPI() throws {
        let textAndInputPrivacy: TextAndInputPrivacyLevel = .mockRandom()
        let imagePrivacy: ImagePrivacyLevel = .mockRandom()
        let touchPrivacy: TouchPrivacyLevel = .mockRandom()
        config = SessionReplay.Configuration(
            replaySampleRate: 42,
            textAndInputPrivacyLevel: textAndInputPrivacy,
            imagePrivacyLevel: imagePrivacy,
            touchPrivacyLevel: touchPrivacy
        )

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 42)
        XCTAssertEqual(sr.recordingCoordinator.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(sr.recordingCoordinator.imagePrivacy, imagePrivacy)
        XCTAssertEqual(sr.recordingCoordinator.touchPrivacy, touchPrivacy)
        XCTAssertNil((sr.requestBuilder as? SegmentRequestBuilder)?.customUploadURL)
        let r = try XCTUnwrap(core.get(feature: ResourcesFeature.self))
        XCTAssertNil((r.requestBuilder as? ResourceRequestBuilder)?.customUploadURL)
    }

    func testWhenEnabledWithRandomPrivacyLevel() throws {
        let randomPrivacy: SessionReplayPrivacyLevel = .mockRandom()
        config.defaultPrivacyLevel = randomPrivacy

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        let newPrivacyLevels = SessionReplay.Configuration.convertPrivacyLevel(from: randomPrivacy)
        XCTAssertEqual(sr.recordingCoordinator.textAndInputPrivacy, newPrivacyLevels.textAndInputPrivacy)
        XCTAssertEqual(sr.recordingCoordinator.imagePrivacy, newPrivacyLevels.imagePrivacy)
        XCTAssertEqual(sr.recordingCoordinator.touchPrivacy, newPrivacyLevels.touchPrivacy)
    }

    func testWhenEnabledWithReplaySampleRate() throws {
        let random: Float = .mockRandom(min: 0, max: 100)
        config.replaySampleRate = random

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, random)
    }

    func testWhenEnabledWithCustomEndpoint() throws {
        let random: URL = .mockRandom()
        config.customEndpoint = random

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual((sr.requestBuilder as? SegmentRequestBuilder)?.customUploadURL, random)
    }

    func testWhenEnabledWithDebugSDKArgument() throws {
        // Given
        config.replaySampleRate = .mockRandom(min: 0, max: 100)
        config.debugSDK = true

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, 100)
    }

    func testWhenEnabledWithNoDebugSDKArgument() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.replaySampleRate = random
        config.debugSDK = false

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        let sr = try XCTUnwrap(core.get(feature: SessionReplayFeature.self))
        XCTAssertEqual(sr.recordingCoordinator.sampler.samplingRate, random)
    }

    func testItDoesntStartFeatureWhenSamplingRateIsZero() throws {
        // Given
        config.replaySampleRate = 0

        // When
        SessionReplay.enable(with: config, in: core)

        // Then
        XCTAssertNil(core.get(feature: SessionReplayFeature.self))
        XCTAssertNil(core.get(feature: ResourcesFeature.self))
    }

    // MARK: Telemetry

    func testWhenEnabled_itSendsConfigurationTelemetry() throws {
        // Given
        let sampleRate: Int64 = .mockRandom(min: 0, max: 100)
        let privacyLevel: SessionReplayPrivacyLevel = .mockRandom()
        let startRecordingImmediately: Bool = .mockRandom()
        let messageReceiver = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: messageReceiver)

        // When
        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: Float(sampleRate),
                defaultPrivacyLevel: privacyLevel,
                startRecordingImmediately: startRecordingImmediately
            ),
            in: core
        )

        // Then
        let configuration = try XCTUnwrap(messageReceiver.messages.firstTelemetry?.asConfiguration)
        XCTAssertEqual(configuration.sessionReplaySampleRate, sampleRate)
        XCTAssertNil(configuration.defaultPrivacyLevel)
        let newPrivacyLevels = SessionReplay.Configuration.convertPrivacyLevel(from: privacyLevel)
        XCTAssertEqual(configuration.textAndInputPrivacyLevel, newPrivacyLevels.textAndInputPrivacy.rawValue)
        XCTAssertEqual(configuration.imagePrivacyLevel, newPrivacyLevels.imagePrivacy.rawValue)
        XCTAssertEqual(configuration.touchPrivacyLevel, newPrivacyLevels.touchPrivacy.rawValue)
        XCTAssertEqual(configuration.startRecordingImmediately, startRecordingImmediately)
    }

    func testWhenEnabled_itSendsConfigurationTelemetry_withNewApi() throws {
        // Given
        let sampleRate: Int64 = .mockRandom(min: 0, max: 100)
        let textAndInputLevel: TextAndInputPrivacyLevel = .mockRandom()
        let imageLevel: ImagePrivacyLevel = .mockRandom()
        let touchLevel: TouchPrivacyLevel = .mockRandom()
        let startRecordingImmediately: Bool = .mockRandom()
        let messageReceiver = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: messageReceiver)

        // When
        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: Float(sampleRate),
                textAndInputPrivacyLevel: textAndInputLevel,
                imagePrivacyLevel: imageLevel,
                touchPrivacyLevel: touchLevel,
                startRecordingImmediately: startRecordingImmediately
            ),
            in: core
        )

        // Then
        let configuration = try XCTUnwrap(messageReceiver.messages.firstTelemetry?.asConfiguration)
        XCTAssertEqual(configuration.sessionReplaySampleRate, sampleRate)
        XCTAssertNil(configuration.defaultPrivacyLevel)
        XCTAssertEqual(configuration.textAndInputPrivacyLevel, textAndInputLevel.rawValue)
        XCTAssertEqual(configuration.imagePrivacyLevel, imageLevel.rawValue)
        XCTAssertEqual(configuration.touchPrivacyLevel, touchLevel.rawValue)
        XCTAssertEqual(configuration.startRecordingImmediately, startRecordingImmediately)
    }

    // MARK: - Recording Tests

    func testWhenStartInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        SessionReplay.startRecording(in: NOPDatadogCore())

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Session Replay must be initialized before calling `SessionReplay.startRecording()`."
        )
    }
}
#endif
