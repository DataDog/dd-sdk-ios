/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

@testable import DatadogRUM
@testable import TestUtilities
import XCTest
#if os(macOS)
import AppKit
#endif

final class AccessibilityReaderTests: XCTestCase {
    #if !os(macOS)
    @MainActor
    func testInitialStateIsPopulated() {
        // Given
        let reader = AccessibilityReader(notificationCenter: .init())

        // Then
        let expectation = XCTestExpectation(description: "Initial state populated")
        DispatchQueue.main.async {
            let state = reader.state
            XCTAssertNotNil(state.textSize)
            XCTAssertNotNil(state.screenReaderEnabled)
            XCTAssertNotNil(state.boldTextEnabled)
            XCTAssertNotNil(state.reduceTransparencyEnabled)
            XCTAssertNotNil(state.reduceMotionEnabled)
            XCTAssertNotNil(state.invertColorsEnabled)
            XCTAssertNotNil(state.increaseContrastEnabled)
            XCTAssertNotNil(state.assistiveSwitchEnabled)
            XCTAssertNotNil(state.assistiveTouchEnabled)
            XCTAssertNotNil(state.videoAutoplayEnabled)
            XCTAssertNotNil(state.closedCaptioningEnabled)
            XCTAssertNotNil(state.monoAudioEnabled)
            XCTAssertNotNil(state.shakeToUndoEnabled)
            XCTAssertNotNil(state.shouldDifferentiateWithoutColor)
            XCTAssertNotNil(state.grayscaleEnabled)
            XCTAssertNotNil(state.singleAppModeEnabled)
            XCTAssertNotNil(state.onOffSwitchLabelsEnabled)
            XCTAssertNotNil(state.speakScreenEnabled)
            XCTAssertNotNil(state.speakSelectionEnabled)
            XCTAssertNotNil(state.rtlEnabled)

            XCTAssertNotNil(state.buttonShapesEnabled)
            XCTAssertNotNil(state.reducedAnimationsEnabled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testRegistersAllObservers() {
        // Given
        let mockNotificationCenter = MockNotificationCenter()
        _ = AccessibilityReader(notificationCenter: mockNotificationCenter)

        let observerNames = mockNotificationCenter.getObserverNames()

        // Then
        XCTAssertTrue(observerNames.contains(UIAccessibility.voiceOverStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.switchControlStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.assistiveTouchStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.boldTextStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.closedCaptioningStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.reduceTransparencyStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.reduceMotionStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.invertColorsStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.darkerSystemColorsStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.monoAudioStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.shakeToUndoDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.grayscaleStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.guidedAccessStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.speakScreenStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.speakSelectionStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.videoAutoplayStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.differentiateWithoutColorDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.onOffSwitchLabelsDidChangeNotification))
    }

    func testRegistersIOS14Observers() {
        // Given
        let mockNotificationCenter = MockNotificationCenter()
        _ = AccessibilityReader(notificationCenter: mockNotificationCenter)

        let observerNames = mockNotificationCenter.getObserverNames()

        // Then
        XCTAssertTrue(observerNames.contains(UIAccessibility.buttonShapesEnabledStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.prefersCrossFadeTransitionsStatusDidChange))
    }
    #endif

    @MainActor
    func testAccessibilityReaderProtocolConformance() {
        // Given
        let reader: AccessibilityReading = AccessibilityReader(notificationCenter: .init())

        // When
        let state = reader.state

        // Then
        XCTAssertNotNil(state)
    }

    func testAccessibilityInfoToRUMConversion() {
        // Given - Non-empty state
        let nonEmptyState = AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false
        )
        let mockReader = AccessibilityReaderMock(state: nonEmptyState)

        // When
        let accessibility = mockReader.state.rumViewAccessibility

        // Then - Should return RUM accessibility object
        XCTAssertNotNil(accessibility)
        XCTAssertEqual(accessibility?.textSize, "large")
        XCTAssertEqual(accessibility?.screenReaderEnabled, true)
        XCTAssertEqual(accessibility?.boldTextEnabled, false)
    }

    func testEmptyAccessibilityInfoToRUMConversion() {
        // Given - Empty state
        let mockReader = AccessibilityReaderMock(state: AccessibilityInfo())

        // When
        let accessibility = mockReader.state.rumViewAccessibility

        // Then - Should return nil when no valid data
        XCTAssertNil(accessibility)
    }

    func testAccessibilityInfoDifferences() {
        // Given - Initial state
        let initialState = AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false,
            reduceTransparencyEnabled: false,
            reduceMotionEnabled: false
        )

        // When - New state with some changes
        let newState = AccessibilityInfo(
            textSize: "large", // Same
            screenReaderEnabled: true, // Same
            boldTextEnabled: true, // Changed
            reduceTransparencyEnabled: true, // Changed
            reduceMotionEnabled: false // Same
        )

        let differences = newState.differences(from: initialState)

        // Then - Should only include changed values
        let rumDifferences = differences.rumViewAccessibility
        XCTAssertNotNil(rumDifferences)
        XCTAssertEqual(rumDifferences?.boldTextEnabled, true)
        XCTAssertEqual(rumDifferences?.reduceTransparencyEnabled, true)
        XCTAssertNil(rumDifferences?.textSize)
        XCTAssertNil(rumDifferences?.screenReaderEnabled)
        XCTAssertNil(rumDifferences?.reduceMotionEnabled)
    }

    func testAccessibilityInfoDifferencesFromNil() {
        // Given
        let currentState = AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false
        )

        // When - Compare with nil (no previous state)
        let differences = currentState.differences(from: nil)

        // Then - Should return the entire current state
        let rumDifferences = differences.rumViewAccessibility
        XCTAssertNotNil(rumDifferences)
        XCTAssertEqual(rumDifferences?.textSize, "large")
        XCTAssertEqual(rumDifferences?.screenReaderEnabled, true)
        XCTAssertEqual(rumDifferences?.boldTextEnabled, false)
    }

    func testAccessibilityInfoNoDifferences() {
        // Given - Two identical states
        let state1 = AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false
        )
        let state2 = AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false
        )

        // When
        let differences = state2.differences(from: state1)

        // Then - Should return empty (no differences)
        let rumDifferences = differences.rumViewAccessibility
        XCTAssertNil(rumDifferences)
    }

    #if os(macOS)
    @MainActor
    func testWhenAllSettingsAreOn_itReportsTheMacOSSettingsAndLeavesTheOthersUnknown() {
        // Given
        let settings = MacOSAccessibilitySettingsMock(allEnabled: true)

        // When
        let reader = AccessibilityReader(notificationCenter: MockNotificationCenter(), settings: settings, layoutDirection: { .rightToLeft })
        let state = waitForState(of: reader) { $0.hasAccessibilityData }

        // Then
        XCTAssertEqual(state.increaseContrastEnabled, true)
        XCTAssertEqual(state.shouldDifferentiateWithoutColor, true)
        XCTAssertEqual(state.reduceTransparencyEnabled, true)
        XCTAssertEqual(state.reduceMotionEnabled, true)
        XCTAssertEqual(state.invertColorsEnabled, true)
        XCTAssertEqual(state.screenReaderEnabled, true)
        XCTAssertEqual(state.assistiveSwitchEnabled, true)
        XCTAssertEqual(state.rtlEnabled, true)
        XCTAssertNil(state.textSize)
        XCTAssertNil(state.boldTextEnabled)
        XCTAssertNil(state.buttonShapesEnabled)
        XCTAssertNil(state.assistiveTouchEnabled)
        XCTAssertNil(state.videoAutoplayEnabled)
        XCTAssertNil(state.closedCaptioningEnabled)
        XCTAssertNil(state.monoAudioEnabled)
        XCTAssertNil(state.shakeToUndoEnabled)
        XCTAssertNil(state.reducedAnimationsEnabled)
        XCTAssertNil(state.grayscaleEnabled)
        XCTAssertNil(state.singleAppModeEnabled)
        XCTAssertNil(state.onOffSwitchLabelsEnabled)
        XCTAssertNil(state.speakScreenEnabled)
        XCTAssertNil(state.speakSelectionEnabled)
    }

    @MainActor
    func testWhenAllSettingsAreOff_itReportsThemAsDisabled() {
        // Given
        let settings = MacOSAccessibilitySettingsMock(allEnabled: false)

        // When
        let reader = AccessibilityReader(notificationCenter: MockNotificationCenter(), settings: settings, layoutDirection: { .leftToRight })
        let state = waitForState(of: reader) { $0.hasAccessibilityData }

        // Then
        XCTAssertEqual(state.increaseContrastEnabled, false)
        XCTAssertEqual(state.shouldDifferentiateWithoutColor, false)
        XCTAssertEqual(state.reduceTransparencyEnabled, false)
        XCTAssertEqual(state.reduceMotionEnabled, false)
        XCTAssertEqual(state.invertColorsEnabled, false)
        XCTAssertEqual(state.screenReaderEnabled, false)
        XCTAssertEqual(state.assistiveSwitchEnabled, false)
        XCTAssertEqual(state.rtlEnabled, false)
    }

    @MainActor
    func testWhenTheLayoutDirectionIsUnknown_rightToLeftStaysUnknown() {
        // Given
        let settings = MacOSAccessibilitySettingsMock(allEnabled: false)

        // When
        let reader = AccessibilityReader(notificationCenter: MockNotificationCenter(), settings: settings, layoutDirection: { nil })
        let state = waitForState(of: reader) { $0.hasAccessibilityData }

        // Then
        XCTAssertNil(state.rtlEnabled)
    }

    @MainActor
    func testWhenDisplayOptionsChange_itReadsTheSettingsAgain() {
        // Given
        let notificationCenter = MockNotificationCenter()
        let settings = MacOSAccessibilitySettingsMock(allEnabled: false)
        let reader = AccessibilityReader(notificationCenter: notificationCenter, settings: settings, layoutDirection: { nil })
        _ = waitForState(of: reader) { $0.hasAccessibilityData }

        // When
        settings.accessibilityDisplayShouldReduceMotion = true
        notificationCenter.postFakeNotification(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)

        // Then
        let state = waitForState(of: reader) { $0.reduceMotionEnabled == true }
        XCTAssertEqual(state.reduceMotionEnabled, true)
    }

    @MainActor
    func testWhenVoiceOverIsTurnedOn_itReadsTheSettingsAgain() {
        // Given
        let settings = MacOSAccessibilitySettingsMock(allEnabled: false)
        let reader = AccessibilityReader(notificationCenter: MockNotificationCenter(), settings: settings, layoutDirection: { nil })
        _ = waitForState(of: reader) { $0.hasAccessibilityData }

        // When
        settings.isVoiceOverEnabled = true
        settings.notifyAssistiveTechnologiesChange()

        // Then
        let state = waitForState(of: reader) { $0.screenReaderEnabled == true }
        XCTAssertEqual(state.screenReaderEnabled, true)
    }

    func testItObservesDisplayOptionsOnTheGivenNotificationCenter() {
        // Given
        let notificationCenter = MockNotificationCenter()

        // When
        _ = AccessibilityReader(notificationCenter: notificationCenter, settings: MacOSAccessibilitySettingsMock(allEnabled: false))

        // Then
        XCTAssertEqual(notificationCenter.getObserverNames(), [NSWorkspace.accessibilityDisplayOptionsDidChangeNotification])
    }

    /// Waits until the state, which the reader updates on the main actor, satisfies `condition`.
    @MainActor
    private func waitForState(of reader: AccessibilityReader, _ condition: @escaping (AccessibilityInfo) -> Bool) -> AccessibilityInfo {
        let updated = expectation(description: "state updated")
        wait(until: { condition(reader.state) }, andThenFulfill: updated)
        wait(for: [updated], timeout: 2)
        return reader.state
    }
    #endif
}

#if os(macOS)
private final class MacOSAccessibilitySettingsMock: MacOSAccessibilitySettings {
    var accessibilityDisplayShouldIncreaseContrast: Bool
    var accessibilityDisplayShouldDifferentiateWithoutColor: Bool
    var accessibilityDisplayShouldReduceTransparency: Bool
    var accessibilityDisplayShouldReduceMotion: Bool
    var accessibilityDisplayShouldInvertColors: Bool
    var isVoiceOverEnabled: Bool
    var isSwitchControlEnabled: Bool
    private var onAssistiveTechnologiesChange: (() -> Void)?

    init(allEnabled: Bool) {
        accessibilityDisplayShouldIncreaseContrast = allEnabled
        accessibilityDisplayShouldDifferentiateWithoutColor = allEnabled
        accessibilityDisplayShouldReduceTransparency = allEnabled
        accessibilityDisplayShouldReduceMotion = allEnabled
        accessibilityDisplayShouldInvertColors = allEnabled
        isVoiceOverEnabled = allEnabled
        isSwitchControlEnabled = allEnabled
    }

    func observeAssistiveTechnologies(_ onChange: @escaping () -> Void) -> [NSObjectProtocol] {
        onAssistiveTechnologiesChange = onChange
        return []
    }

    func notifyAssistiveTechnologiesChange() {
        onAssistiveTechnologiesChange?()
    }
}
#endif

#endif
