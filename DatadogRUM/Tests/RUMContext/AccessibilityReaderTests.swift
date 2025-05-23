/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogRUM
import XCTest

final class AccessibilityReaderTests: XCTestCase {
    // MARK: - Test Helpers

    final class MockNotificationCenter: NotificationCenter, @unchecked Sendable {
        private(set) var observers: [(name: Notification.Name?, object: Any?, queue: OperationQueue?, block: (Notification) -> Void)] = []

        override func addObserver(forName name: Notification.Name?, object: Any?, queue: OperationQueue?, using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            let observer = NSObject()
            observers.append((name, object, queue, block))
            return observer
        }

        func postFakeNotification(name: Notification.Name) {
            for observer in observers where observer.name == name {
                observer.block(Notification(name: name))
            }
        }

        func getObserverNames() -> [Notification.Name] {
            observers.compactMap(\.name)
        }
    }

    // MARK: - Tests

    func testInitialStateIsEmpty() {
        let reader = AccessibilityReader(notificationCenter: .init())
        let state = reader.state

        XCTAssertNil(state.textSize)
        XCTAssertNil(state.screenReaderEnabled)
        XCTAssertNil(state.boldTextEnabled)
        XCTAssertNil(state.reduceTransparencyEnabled)
        XCTAssertNil(state.reduceMotionEnabled)
        XCTAssertNil(state.buttonShapesEnabled)
        XCTAssertNil(state.invertColorsEnabled)
        XCTAssertNil(state.increaseContrastEnabled)
        XCTAssertNil(state.assistiveSwitchEnabled)
        XCTAssertNil(state.assistiveTouchEnabled)
        XCTAssertNil(state.videoAutoplayEnabled)
        XCTAssertNil(state.closedCaptioningEnabled)
        XCTAssertNil(state.monoAudioEnabled)
        XCTAssertNil(state.shakeToUndoEnabled)
        XCTAssertNil(state.reducedAnimationsEnabled)
        XCTAssertNil(state.shouldDifferentiateWithoutColor)
        XCTAssertNil(state.grayscaleEnabled)
        XCTAssertNil(state.singleAppModeEnabled)
        XCTAssertNil(state.onOffSwitchLabelsEnabled)
        XCTAssertNil(state.speakScreenEnabled)
        XCTAssertNil(state.speakSelectionEnabled)
        XCTAssertNil(state.rtlEnabled)
    }

    func testRegistersAllObservers() {
        let mockNotificationCenter = MockNotificationCenter()
        _ = AccessibilityReader(notificationCenter: mockNotificationCenter)

        let observerNames = mockNotificationCenter.getObserverNames()

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
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testRegistersIOS13Observers() {
        let mockNotificationCenter = MockNotificationCenter()
        _ = AccessibilityReader(notificationCenter: mockNotificationCenter)

        let observerNames = mockNotificationCenter.getObserverNames()

        XCTAssertTrue(observerNames.contains(UIAccessibility.videoAutoplayStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.differentiateWithoutColorDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.onOffSwitchLabelsDidChangeNotification))
    }

    @available(iOS 14.0, tvOS 14.0, *)
    func testRegistersIOS14Observers() {
        let mockNotificationCenter = MockNotificationCenter()
        _ = AccessibilityReader(notificationCenter: mockNotificationCenter)

        let observerNames = mockNotificationCenter.getObserverNames()

        XCTAssertTrue(observerNames.contains(UIAccessibility.buttonShapesEnabledStatusDidChangeNotification))
        XCTAssertTrue(observerNames.contains(UIAccessibility.prefersCrossFadeTransitionsStatusDidChange))
    }

    @MainActor
    func testStateUpdatesWhenNotificationIsSent() {
        // Given
        let mockNotificationCenter = MockNotificationCenter()
        let mockValues = MockAccessibilityValues()
        let reader = AccessibilityReader(notificationCenter: mockNotificationCenter, accessibilityValues: mockValues)

        // When
        mockValues.isVoiceOverRunning = true
        mockValues.textSize = "extra-large"
        mockNotificationCenter.postFakeNotification(name: UIAccessibility.voiceOverStatusDidChangeNotification)

        // Then
        let expectation = XCTestExpectation(description: "State updated")
        DispatchQueue.main.async {
            XCTAssertEqual(reader.state.screenReaderEnabled, true)
            XCTAssertEqual(reader.state.textSize, "extra-large")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testAccessibilityValuesArePropagated() {
        // Given
        let mock = MockAccessibilityValues()
        mock.textSize = "large"
        mock.isVoiceOverRunning = true
        mock.isBoldTextEnabled = true
        mock.isReduceTransparencyEnabled = true
        mock.isReduceMotionEnabled = true
        mock.buttonShapesEnabled = true
        mock.isInvertColorsEnabled = true
        mock.isDarkerSystemColorsEnabled = true
        mock.isSwitchControlRunning = true
        mock.isAssistiveTouchRunning = true
        mock.isVideoAutoplayEnabled = true
        mock.isClosedCaptioningEnabled = true
        mock.isMonoAudioEnabled = true
        mock.isShakeToUndoEnabled = true
        mock.prefersCrossFadeTransitions = true
        mock.shouldDifferentiateWithoutColor = true
        mock.isGrayscaleEnabled = true
        mock.isGuidedAccessEnabled = true
        mock.isOnOffSwitchLabelsEnabled = true
        mock.isSpeakScreenEnabled = true
        mock.isSpeakSelectionEnabled = true
        mock.rtlEnabled = true

        // When
        let reader = AccessibilityReader(notificationCenter: .init(), accessibilityValues: mock)
        reader.updateState()

        // Then
        let expectation = XCTestExpectation(description: "State updated")
        DispatchQueue.main.async {
            let state = reader.state
            XCTAssertEqual(state.textSize, "large")
            XCTAssertEqual(state.screenReaderEnabled, true)
            XCTAssertEqual(state.boldTextEnabled, true)
            XCTAssertEqual(state.reduceMotionEnabled, true)
            XCTAssertEqual(state.buttonShapesEnabled, true)
            XCTAssertEqual(state.invertColorsEnabled, true)
            XCTAssertEqual(state.increaseContrastEnabled, true)
            XCTAssertEqual(state.assistiveSwitchEnabled, true)
            XCTAssertEqual(state.assistiveTouchEnabled, true)
            XCTAssertEqual(state.videoAutoplayEnabled, true)
            XCTAssertEqual(state.closedCaptioningEnabled, true)
            XCTAssertEqual(state.monoAudioEnabled, true)
            XCTAssertEqual(state.shakeToUndoEnabled, true)
            XCTAssertEqual(state.reducedAnimationsEnabled, true)
            XCTAssertEqual(state.shouldDifferentiateWithoutColor, true)
            XCTAssertEqual(state.grayscaleEnabled, true)
            XCTAssertEqual(state.singleAppModeEnabled, true)
            XCTAssertEqual(state.onOffSwitchLabelsEnabled, true)
            XCTAssertEqual(state.speakScreenEnabled, true)
            XCTAssertEqual(state.speakSelectionEnabled, true)
            XCTAssertEqual(state.rtlEnabled, true)
            expectation.fulfill()
        }
        reader.updateState()
        wait(for: [expectation], timeout: 1.0)
    }
}
