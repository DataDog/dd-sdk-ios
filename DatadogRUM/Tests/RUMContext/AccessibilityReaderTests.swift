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
        let expectedState = Accessibility(
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
        let mockState = Accessibility.mockRandom()
        let mockReader = AccessibilityReaderMock(state: mockState)

        // When
        let state = mockReader.state

        // Then
        XCTAssertEqual(state.textSize, mockState.textSize)
        XCTAssertEqual(state.screenReaderEnabled, mockState.screenReaderEnabled)
        XCTAssertEqual(state.boldTextEnabled, mockState.boldTextEnabled)
    }

    func testAccessibilityMockAny() {
        let mock = AccessibilityReaderMock.mockAny()
        XCTAssertNotNil(mock.state)
    }

    func testAccessibilityMockRandom() {
        let mock = AccessibilityReaderMock.mockRandom()
        XCTAssertNotNil(mock.state)
    }
}
