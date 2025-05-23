/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

final class AccessibilityReaderTests: XCTestCase {
    // MARK: - Test Helpers
    class TestableAccessibilityReader: AccessibilityReader {
        private var mockState: Accessibility?
        private(set) var updateCount = 0
        private var stateUpdateExpectation: XCTestExpectation?

        override func updateState() {
            updateCount += 1
            if let mockState = mockState {
                DispatchQueue.main.async {
                    self.state = mockState
                    self.stateUpdateExpectation?.fulfill()
                }
            } else {
                super.updateState()
            }
        }

        func setMockState(_ state: Accessibility, expectation: XCTestExpectation? = nil) {
            mockState = state
            stateUpdateExpectation = expectation
        }
    }

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
            return observers.compactMap { $0.name }
        }

        // Method to replace an observer's callback for testing
        func replaceObserverCallback(for notificationName: Notification.Name, with newCallback: @escaping (Notification) -> Void) -> Bool {
            if let index = observers.firstIndex(where: { $0.name == notificationName }) {
                let oldObserver = observers[index]
                observers[index] = (
                    name: oldObserver.name,
                    object: oldObserver.object,
                    queue: oldObserver.queue,
                    block: newCallback
                )
                return true
            }
            return false
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

        // Test core observers that should always be registered
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

    func testNotificationTriggersStateUpdate() {
        let mockNotificationCenter = MockNotificationCenter()
        let reader = TestableAccessibilityReader(notificationCenter: mockNotificationCenter)

        // Set up a mock state that will be applied when updateState is called
        var mockState = Accessibility()
        mockState.screenReaderEnabled = true
        mockState.textSize = "extra-large"
        mockState.reduceMotionEnabled = false

        let expectation = XCTestExpectation(description: "State updated after notification")
        reader.setMockState(mockState, expectation: expectation)

        // Verify initial state is different from our mock state
        XCTAssertNil(reader.state.screenReaderEnabled, "Initial state should be nil")
        XCTAssertNil(reader.state.textSize, "Initial state should be nil")
        XCTAssertNil(reader.state.reduceMotionEnabled, "Initial state should be nil")
        XCTAssertEqual(reader.updateCount, 1, "Should have initial update from init")

        // Post the notification that should trigger state update
        mockNotificationCenter.postFakeNotification(name: UIAccessibility.voiceOverStatusDidChangeNotification)

        wait(for: [expectation], timeout: 1.0)

        // Verify the state was actually updated to our mock state
        XCTAssertEqual(reader.updateCount, 2, "Should have triggered one additional update")
        XCTAssertEqual(reader.state.screenReaderEnabled, true, "State should be updated")
        XCTAssertEqual(reader.state.textSize, "extra-large", "State should be updated")
        XCTAssertEqual(reader.state.reduceMotionEnabled, false, "State should be updated")
    }

    func testMultipleNotificationsIncrementUpdateCount() {
        let mockNotificationCenter = MockNotificationCenter()
        let reader = TestableAccessibilityReader(notificationCenter: mockNotificationCenter)

        // Set up initial mock state
        var mockState = Accessibility()
        mockState.screenReaderEnabled = false
        mockState.boldTextEnabled = false
        mockState.reduceMotionEnabled = false

        // Set mock state without expectation since we're not triggering an update yet
        reader.setMockState(mockState)

        let initialUpdateCount = reader.updateCount // Should be 1 from init

        // Verify initial state (should still be nil since no notifications have been posted)
        XCTAssertNil(reader.state.screenReaderEnabled, "Initial screenReader should be nil")
        XCTAssertNil(reader.state.boldTextEnabled, "Initial boldText should be nil")
        XCTAssertNil(reader.state.reduceMotionEnabled, "Initial reduceMotion should be nil")

        // FIRST NOTIFICATION: VoiceOver - update screenReaderEnabled
        mockState.screenReaderEnabled = true
        let firstExpectation = XCTestExpectation(description: "First update processed")
        reader.setMockState(mockState, expectation: firstExpectation)

        mockNotificationCenter.postFakeNotification(name: UIAccessibility.voiceOverStatusDidChangeNotification)
        wait(for: [firstExpectation], timeout: 1.0)

        // Verify state after first notification
        XCTAssertEqual(reader.updateCount, initialUpdateCount + 1, "Should have 1 additional update")
        XCTAssertEqual(reader.state.screenReaderEnabled, true, "ScreenReader should be updated to true")
        XCTAssertEqual(reader.state.boldTextEnabled, false, "BoldText should remain false")
        XCTAssertEqual(reader.state.reduceMotionEnabled, false, "ReduceMotion should remain false")

        // SECOND NOTIFICATION: Bold Text - update boldTextEnabled
        mockState.boldTextEnabled = true
        let secondExpectation = XCTestExpectation(description: "Second update processed")
        reader.setMockState(mockState, expectation: secondExpectation)

        mockNotificationCenter.postFakeNotification(name: UIAccessibility.boldTextStatusDidChangeNotification)
        wait(for: [secondExpectation], timeout: 1.0)

        // Verify state after second notification
        XCTAssertEqual(reader.updateCount, initialUpdateCount + 2, "Should have 2 additional updates")
        XCTAssertEqual(reader.state.screenReaderEnabled, true, "ScreenReader should remain true")
        XCTAssertEqual(reader.state.boldTextEnabled, true, "BoldText should be updated to true")
        XCTAssertEqual(reader.state.reduceMotionEnabled, false, "ReduceMotion should remain false")

        // THIRD NOTIFICATION: Reduce Motion - update reduceMotionEnabled
        mockState.reduceMotionEnabled = true
        let thirdExpectation = XCTestExpectation(description: "Third update processed")
        reader.setMockState(mockState, expectation: thirdExpectation)

        mockNotificationCenter.postFakeNotification(name: UIAccessibility.reduceMotionStatusDidChangeNotification)
        wait(for: [thirdExpectation], timeout: 1.0)

        // Verify final state after all notifications
        XCTAssertEqual(reader.updateCount, initialUpdateCount + 3, "Should have triggered 3 additional updates")
        XCTAssertEqual(reader.state.screenReaderEnabled, true, "ScreenReader should remain true")
        XCTAssertEqual(reader.state.boldTextEnabled, true, "BoldText should remain true")
        XCTAssertEqual(reader.state.reduceMotionEnabled, true, "ReduceMotion should be updated to true")
    }
}
