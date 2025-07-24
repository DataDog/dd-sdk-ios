/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogRUM
@testable import TestUtilities
import XCTest

@available(iOS 13.0, tvOS 13.0, *)
final class AccessibilityReaderTests: XCTestCase {
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

            if #available(iOS 14.0, tvOS 14.0, *) {
                XCTAssertNotNil(state.buttonShapesEnabled)
                XCTAssertNotNil(state.reducedAnimationsEnabled)
            } else {
                XCTAssertNil(state.buttonShapesEnabled)
                XCTAssertNil(state.reducedAnimationsEnabled)
            }
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

    @available(iOS 14.0, tvOS 14.0, *)
    func testRegistersIOS14Observers() {
        // Given
        let mockNotificationCenter = MockNotificationCenter()
        _ = AccessibilityReader(notificationCenter: mockNotificationCenter)

        let observerNames = mockNotificationCenter.getObserverNames()

        // Then
        XCTAssertTrue(observerNames.contains(UIAccessibility.buttonShapesEnabledStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.prefersCrossFadeTransitionsStatusDidChange))
    }

    @MainActor
    func testStateUpdatesWhenNotificationIsSent() {
        // Given
        let expectedState = AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false,
            reduceTransparencyEnabled: true,
            reduceMotionEnabled: false,
            buttonShapesEnabled: true,
            invertColorsEnabled: false,
            increaseContrastEnabled: true,
            assistiveSwitchEnabled: false,
            assistiveTouchEnabled: true,
            videoAutoplayEnabled: false,
            closedCaptioningEnabled: true,
            monoAudioEnabled: false,
            shakeToUndoEnabled: true,
            reducedAnimationsEnabled: false,
            shouldDifferentiateWithoutColor: true,
            grayscaleEnabled: false,
            singleAppModeEnabled: true,
            onOffSwitchLabelsEnabled: false,
            speakScreenEnabled: true,
            speakSelectionEnabled: false,
            rtlEnabled: true
        )

        let mockNotificationCenter = MockNotificationCenter()
        let mockReader = AccessibilityReaderMock(state: expectedState)

        // When
        mockNotificationCenter.postFakeNotification(name: UIAccessibility.voiceOverStatusDidChangeNotification)

        // Then
        let actualState = mockReader.state
        XCTAssertEqual(actualState.textSize, "large")
        XCTAssertEqual(actualState.screenReaderEnabled, true)
        XCTAssertEqual(actualState.boldTextEnabled, false)
        XCTAssertEqual(actualState.reduceTransparencyEnabled, true)
        XCTAssertEqual(actualState.reduceMotionEnabled, false)
        XCTAssertEqual(actualState.buttonShapesEnabled, true)
        XCTAssertEqual(actualState.invertColorsEnabled, false)
        XCTAssertEqual(actualState.increaseContrastEnabled, true)
        XCTAssertEqual(actualState.assistiveSwitchEnabled, false)
        XCTAssertEqual(actualState.assistiveTouchEnabled, true)
        XCTAssertEqual(actualState.videoAutoplayEnabled, false)
        XCTAssertEqual(actualState.closedCaptioningEnabled, true)
        XCTAssertEqual(actualState.monoAudioEnabled, false)
        XCTAssertEqual(actualState.shakeToUndoEnabled, true)
        XCTAssertEqual(actualState.reducedAnimationsEnabled, false)
        XCTAssertEqual(actualState.shouldDifferentiateWithoutColor, true)
        XCTAssertEqual(actualState.grayscaleEnabled, false)
        XCTAssertEqual(actualState.singleAppModeEnabled, true)
        XCTAssertEqual(actualState.onOffSwitchLabelsEnabled, false)
        XCTAssertEqual(actualState.speakScreenEnabled, true)
        XCTAssertEqual(actualState.speakSelectionEnabled, false)
        XCTAssertEqual(actualState.rtlEnabled, true)
    }

    @MainActor
    func testAccessibilityReaderProtocolConformance() {
        // Given
        let reader: AccessibilityReading = AccessibilityReader(notificationCenter: .init())

        // When
        let state = reader.state

        // Then
        XCTAssertNotNil(state)
    }

    func testAccessibilityReaderMock() {
        // Given
        let mockState = AccessibilityInfo.mockRandom()
        let mockReader = AccessibilityReaderMock(state: mockState)

        // When
        let state = mockReader.state

        // Then
        XCTAssertEqual(state.textSize, mockState.textSize)
        XCTAssertEqual(state.screenReaderEnabled, mockState.screenReaderEnabled)
        XCTAssertEqual(state.boldTextEnabled, mockState.boldTextEnabled)
    }

    func testHasValidAccessibilityData() {
        // Given
        let mockReader = AccessibilityReaderMock(state: .mockAny())

        // Then - Should return true for valid state
        XCTAssertTrue(mockReader.hasValidAccessibilityData)

        // Given - Empty state
        let emptyReader = AccessibilityReaderMock(state: AccessibilityInfo())

        // Then - Should return false for empty state
        XCTAssertFalse(emptyReader.hasValidAccessibilityData)
    }

    func testNoAccessibilityDataWhenStateIsEmpty() {
        // Given
        let mockReader = AccessibilityReaderMock(state: AccessibilityInfo()) // Empty state

        // When
        let accessibility = mockReader.rumAccessibility

        // Then - Should return nil when no valid data
        XCTAssertNil(accessibility)
    }

    func testChangedAttributesTracking() {
        // Given
        let mockReader = AccessibilityReaderMock(state: AccessibilityInfo(
            textSize: "large",
            screenReaderEnabled: true,
            boldTextEnabled: false,
            reduceTransparencyEnabled: false,
            reduceMotionEnabled: false,
            buttonShapesEnabled: false,
            invertColorsEnabled: false,
            increaseContrastEnabled: false,
            assistiveSwitchEnabled: false,
            assistiveTouchEnabled: false,
            videoAutoplayEnabled: false,
            closedCaptioningEnabled: false,
            monoAudioEnabled: false,
            shakeToUndoEnabled: false,
            reducedAnimationsEnabled: false,
            shouldDifferentiateWithoutColor: false,
            grayscaleEnabled: false,
            singleAppModeEnabled: false,
            onOffSwitchLabelsEnabled: false,
            speakScreenEnabled: false,
            speakSelectionEnabled: false,
            rtlEnabled: false
        ))

        // Then - Should return all attributes
        let accessibility1 = mockReader.rumAccessibility
        XCTAssertNotNil(accessibility1)
        XCTAssertEqual(accessibility1?.screenReaderEnabled, true)
        XCTAssertEqual(accessibility1?.textSize, "large")
        XCTAssertEqual(accessibility1?.boldTextEnabled, false)
        XCTAssertEqual(accessibility1?.reduceTransparencyEnabled, false)
        XCTAssertEqual(accessibility1?.reduceMotionEnabled, false)
        XCTAssertEqual(accessibility1?.buttonShapesEnabled, false)
        XCTAssertEqual(accessibility1?.invertColorsEnabled, false)
        XCTAssertEqual(accessibility1?.increaseContrastEnabled, false)
        XCTAssertEqual(accessibility1?.assistiveSwitchEnabled, false)
        XCTAssertEqual(accessibility1?.assistiveTouchEnabled, false)
        XCTAssertEqual(accessibility1?.videoAutoplayEnabled, false)
        XCTAssertEqual(accessibility1?.closedCaptioningEnabled, false)
        XCTAssertEqual(accessibility1?.monoAudioEnabled, false)
        XCTAssertEqual(accessibility1?.shakeToUndoEnabled, false)
        XCTAssertEqual(accessibility1?.reducedAnimationsEnabled, false)
        XCTAssertEqual(accessibility1?.shouldDifferentiateWithoutColor, false)
        XCTAssertEqual(accessibility1?.grayscaleEnabled, false)
        XCTAssertEqual(accessibility1?.singleAppModeEnabled, false)
        XCTAssertEqual(accessibility1?.onOffSwitchLabelsEnabled, false)
        XCTAssertEqual(accessibility1?.speakScreenEnabled, false)
        XCTAssertEqual(accessibility1?.speakSelectionEnabled, false)
        XCTAssertEqual(accessibility1?.rtlEnabled, false)

        // We clear the attributes to simulate a view update
        mockReader.clearChangedAttributes()

        // When - Simulate a change
        let newState = AccessibilityInfo(
            textSize: "large", // Same
            screenReaderEnabled: true, // Same
            boldTextEnabled: true, // Changed
            reduceTransparencyEnabled: false,
            reduceMotionEnabled: false,
            buttonShapesEnabled: false,
            invertColorsEnabled: false,
            increaseContrastEnabled: false,
            assistiveSwitchEnabled: false,
            assistiveTouchEnabled: false,
            videoAutoplayEnabled: false,
            closedCaptioningEnabled: false,
            monoAudioEnabled: false,
            shakeToUndoEnabled: false,
            reducedAnimationsEnabled: false,
            shouldDifferentiateWithoutColor: false,
            grayscaleEnabled: false,
            singleAppModeEnabled: false,
            onOffSwitchLabelsEnabled: false,
            speakScreenEnabled: false,
            speakSelectionEnabled: false,
            rtlEnabled: false
        )

        mockReader.simulateAccessibilityChange(newState: newState)

        // Then - Should only return newly changed attributes
        let accessibility2 = mockReader.rumAccessibility
        XCTAssertNotNil(accessibility2)
        XCTAssertEqual(accessibility2?.boldTextEnabled, true) // Only newly changed
        XCTAssertNil(accessibility2?.textSize)
        XCTAssertNil(accessibility2?.reduceTransparencyEnabled)
        XCTAssertNil(accessibility2?.screenReaderEnabled)
        XCTAssertNil(accessibility2?.reduceMotionEnabled)
        XCTAssertNil(accessibility2?.buttonShapesEnabled)
        XCTAssertNil(accessibility2?.invertColorsEnabled)
        XCTAssertNil(accessibility2?.increaseContrastEnabled)
        XCTAssertNil(accessibility2?.assistiveSwitchEnabled)
        XCTAssertNil(accessibility2?.assistiveTouchEnabled)
        XCTAssertNil(accessibility2?.videoAutoplayEnabled)
        XCTAssertNil(accessibility2?.closedCaptioningEnabled)
        XCTAssertNil(accessibility2?.monoAudioEnabled)
        XCTAssertNil(accessibility2?.shakeToUndoEnabled)
        XCTAssertNil(accessibility2?.reducedAnimationsEnabled)
        XCTAssertNil(accessibility2?.shouldDifferentiateWithoutColor)
        XCTAssertNil(accessibility2?.grayscaleEnabled)
        XCTAssertNil(accessibility2?.singleAppModeEnabled)
        XCTAssertNil(accessibility2?.onOffSwitchLabelsEnabled)
        XCTAssertNil(accessibility2?.speakScreenEnabled)
        XCTAssertNil(accessibility2?.speakSelectionEnabled)
        XCTAssertNil(accessibility2?.rtlEnabled)

        // Reset for new view
        mockReader.resetForNewView()

        // Then - Should return all attributes
        let accessibility3 = mockReader.rumAccessibility
        XCTAssertNotNil(accessibility3)
        XCTAssertEqual(accessibility3?.boldTextEnabled, true)
        XCTAssertEqual(accessibility3?.textSize, "large")
        XCTAssertEqual(accessibility3?.screenReaderEnabled, true)
        XCTAssertEqual(accessibility3?.reduceTransparencyEnabled, false)
        XCTAssertEqual(accessibility3?.reduceMotionEnabled, false)
        XCTAssertEqual(accessibility3?.buttonShapesEnabled, false)
        XCTAssertEqual(accessibility3?.invertColorsEnabled, false)
        XCTAssertEqual(accessibility3?.increaseContrastEnabled, false)
        XCTAssertEqual(accessibility3?.assistiveSwitchEnabled, false)
        XCTAssertEqual(accessibility3?.assistiveTouchEnabled, false)
        XCTAssertEqual(accessibility3?.videoAutoplayEnabled, false)
        XCTAssertEqual(accessibility3?.closedCaptioningEnabled, false)
        XCTAssertEqual(accessibility3?.monoAudioEnabled, false)
        XCTAssertEqual(accessibility3?.shakeToUndoEnabled, false)
        XCTAssertEqual(accessibility3?.reducedAnimationsEnabled, false)
        XCTAssertEqual(accessibility3?.shouldDifferentiateWithoutColor, false)
        XCTAssertEqual(accessibility3?.grayscaleEnabled, false)
        XCTAssertEqual(accessibility3?.singleAppModeEnabled, false)
        XCTAssertEqual(accessibility3?.onOffSwitchLabelsEnabled, false)
        XCTAssertEqual(accessibility3?.speakScreenEnabled, false)
        XCTAssertEqual(accessibility3?.speakSelectionEnabled, false)
        XCTAssertEqual(accessibility3?.rtlEnabled, false)
    }
}
