/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogRUM
@testable import DatadogInternal

extension AccessibilityInfo: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return AccessibilityInfo(
            textSize: .mockAny(),
            screenReaderEnabled: .mockAny(),
            boldTextEnabled: .mockAny(),
            reduceTransparencyEnabled: .mockAny(),
            reduceMotionEnabled: .mockAny(),
            buttonShapesEnabled: .mockAny(),
            invertColorsEnabled: .mockAny(),
            increaseContrastEnabled: .mockAny(),
            assistiveSwitchEnabled: .mockAny(),
            assistiveTouchEnabled: .mockAny(),
            videoAutoplayEnabled: .mockAny(),
            closedCaptioningEnabled: .mockAny(),
            monoAudioEnabled: .mockAny(),
            shakeToUndoEnabled: .mockAny(),
            reducedAnimationsEnabled: .mockAny(),
            shouldDifferentiateWithoutColor: .mockAny(),
            grayscaleEnabled: .mockAny(),
            singleAppModeEnabled: .mockAny(),
            onOffSwitchLabelsEnabled: .mockAny(),
            speakScreenEnabled: .mockAny(),
            speakSelectionEnabled: .mockAny(),
            rtlEnabled: .mockAny()
        )
    }

    public static func mockRandom() -> Self {
        return AccessibilityInfo(
            textSize: ["extraSmall", "small", "medium", "large", "extraLarge", "extraExtraLarge", "extraExtraExtraLarge", "accessibilityMedium", "accessibilityLarge", "accessibilityExtraLarge", "accessibilityExtraExtraLarge", "accessibilityExtraExtraExtraLarge"].randomElement(),
            screenReaderEnabled: .random(),
            boldTextEnabled: .random(),
            reduceTransparencyEnabled: .random(),
            reduceMotionEnabled: .random(),
            buttonShapesEnabled: .random(),
            invertColorsEnabled: .random(),
            increaseContrastEnabled: .random(),
            assistiveSwitchEnabled: .random(),
            assistiveTouchEnabled: .random(),
            videoAutoplayEnabled: .random(),
            closedCaptioningEnabled: .random(),
            monoAudioEnabled: .random(),
            shakeToUndoEnabled: .random(),
            reducedAnimationsEnabled: .random(),
            shouldDifferentiateWithoutColor: .random(),
            grayscaleEnabled: .random(),
            singleAppModeEnabled: .random(),
            onOffSwitchLabelsEnabled: .random(),
            speakScreenEnabled: .random(),
            speakSelectionEnabled: .random(),
            rtlEnabled: .random()
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
public final class AccessibilityReaderMock: AccessibilityReading, AnyMockable, RandomMockable {
    public var state: AccessibilityInfo
    private var changedAttributes: RUMViewEvent.View.Accessibility?

    public init(state: AccessibilityInfo = .mockAny()) {
        self.state = state
    }

    /// Returns all accessibility attributes in RUM View Event format.
    public var allAccessibilityAttributes: RUMViewEvent.View.Accessibility? {
        // Only proceed if we have a valid state (at least one non-nil value)
        guard hasValidAccessibilityData else {
            return nil
        }

        return RUMViewEvent.View.Accessibility(
            assistiveSwitchEnabled: state.assistiveSwitchEnabled,
            assistiveTouchEnabled: state.assistiveTouchEnabled,
            boldTextEnabled: state.boldTextEnabled,
            buttonShapesEnabled: state.buttonShapesEnabled,
            closedCaptioningEnabled: state.closedCaptioningEnabled,
            grayscaleEnabled: state.grayscaleEnabled,
            increaseContrastEnabled: state.increaseContrastEnabled,
            invertColorsEnabled: state.invertColorsEnabled,
            monoAudioEnabled: state.monoAudioEnabled,
            onOffSwitchLabelsEnabled: state.onOffSwitchLabelsEnabled,
            reduceMotionEnabled: state.reduceMotionEnabled,
            reduceTransparencyEnabled: state.reduceTransparencyEnabled,
            reducedAnimationsEnabled: state.reducedAnimationsEnabled,
            rtlEnabled: state.rtlEnabled,
            screenReaderEnabled: state.screenReaderEnabled,
            shakeToUndoEnabled: state.shakeToUndoEnabled,
            shouldDifferentiateWithoutColor: state.shouldDifferentiateWithoutColor,
            singleAppModeEnabled: state.singleAppModeEnabled,
            speakScreenEnabled: state.speakScreenEnabled,
            speakSelectionEnabled: state.speakSelectionEnabled,
            textSize: state.textSize,
            videoAutoplayEnabled: state.videoAutoplayEnabled
        )
    }

    /// Returns only changed accessibility attributes in RUM View Event format.
    public var changedAccessibilityAttributes: RUMViewEvent.View.Accessibility? {
        // Only proceed if we have a valid state (at least one non-nil value)
        guard hasValidAccessibilityData else {
            return nil
        }

        return createAccessibilityFromChangedAttributes()
    }

    /// Called after a view update event has been sent to clear the changed attributes
    public func clearChangedAttributes() {
        changedAttributes = nil
    }

    /// Check if we have valid accessibility data to send
    public var hasValidAccessibilityData: Bool {
        return state.textSize != nil ||
               state.screenReaderEnabled != nil ||
               state.boldTextEnabled != nil ||
               state.reduceTransparencyEnabled != nil ||
               state.reduceMotionEnabled != nil ||
               state.buttonShapesEnabled != nil ||
               state.invertColorsEnabled != nil ||
               state.increaseContrastEnabled != nil ||
               state.assistiveSwitchEnabled != nil ||
               state.assistiveTouchEnabled != nil ||
               state.videoAutoplayEnabled != nil ||
               state.closedCaptioningEnabled != nil ||
               state.monoAudioEnabled != nil ||
               state.shakeToUndoEnabled != nil ||
               state.reducedAnimationsEnabled != nil ||
               state.shouldDifferentiateWithoutColor != nil ||
               state.grayscaleEnabled != nil ||
               state.singleAppModeEnabled != nil ||
               state.onOffSwitchLabelsEnabled != nil ||
               state.speakScreenEnabled != nil ||
               state.speakSelectionEnabled != nil ||
               state.rtlEnabled != nil
    }

    /// Simulate accessibility state change for testing
    public func simulateAccessibilityChange(newState: AccessibilityInfo) {
        // Track changes by comparing with the previous state
        if state != newState {
            changedAttributes = RUMViewEvent.View.Accessibility(
                assistiveSwitchEnabled: state.assistiveSwitchEnabled != newState.assistiveSwitchEnabled ? newState.assistiveSwitchEnabled : nil,
                assistiveTouchEnabled: state.assistiveTouchEnabled != newState.assistiveTouchEnabled ? newState.assistiveTouchEnabled : nil,
                boldTextEnabled: state.boldTextEnabled != newState.boldTextEnabled ? newState.boldTextEnabled : nil,
                buttonShapesEnabled: state.buttonShapesEnabled != newState.buttonShapesEnabled ? newState.buttonShapesEnabled : nil,
                closedCaptioningEnabled: state.closedCaptioningEnabled != newState.closedCaptioningEnabled ? newState.closedCaptioningEnabled : nil,
                grayscaleEnabled: state.grayscaleEnabled != newState.grayscaleEnabled ? newState.grayscaleEnabled : nil,
                increaseContrastEnabled: state.increaseContrastEnabled != newState.increaseContrastEnabled ? newState.increaseContrastEnabled : nil,
                invertColorsEnabled: state.invertColorsEnabled != newState.invertColorsEnabled ? newState.invertColorsEnabled : nil,
                monoAudioEnabled: state.monoAudioEnabled != newState.monoAudioEnabled ? newState.monoAudioEnabled : nil,
                onOffSwitchLabelsEnabled: state.onOffSwitchLabelsEnabled != newState.onOffSwitchLabelsEnabled ? newState.onOffSwitchLabelsEnabled : nil,
                reduceMotionEnabled: state.reduceMotionEnabled != newState.reduceMotionEnabled ? newState.reduceMotionEnabled : nil,
                reduceTransparencyEnabled: state.reduceTransparencyEnabled != newState.reduceTransparencyEnabled ? newState.reduceTransparencyEnabled : nil,
                reducedAnimationsEnabled: state.reducedAnimationsEnabled != newState.reducedAnimationsEnabled ? newState.reducedAnimationsEnabled : nil,
                rtlEnabled: state.rtlEnabled != newState.rtlEnabled ? newState.rtlEnabled : nil,
                screenReaderEnabled: state.screenReaderEnabled != newState.screenReaderEnabled ? newState.screenReaderEnabled : nil,
                shakeToUndoEnabled: state.shakeToUndoEnabled != newState.shakeToUndoEnabled ? newState.shakeToUndoEnabled : nil,
                shouldDifferentiateWithoutColor: state.shouldDifferentiateWithoutColor != newState.shouldDifferentiateWithoutColor ? newState.shouldDifferentiateWithoutColor : nil,
                singleAppModeEnabled: state.singleAppModeEnabled != newState.singleAppModeEnabled ? newState.singleAppModeEnabled : nil,
                speakScreenEnabled: state.speakScreenEnabled != newState.speakScreenEnabled ? newState.speakScreenEnabled : nil,
                speakSelectionEnabled: state.speakSelectionEnabled != newState.speakSelectionEnabled ? newState.speakSelectionEnabled : nil,
                textSize: state.textSize != newState.textSize ? newState.textSize : nil,
                videoAutoplayEnabled: state.videoAutoplayEnabled != newState.videoAutoplayEnabled ? newState.videoAutoplayEnabled : nil
            )
        } else {
            changedAttributes = nil
        }
        state = newState
    }

    /// Create accessibility object from changed attributes only
    private func createAccessibilityFromChangedAttributes() -> RUMViewEvent.View.Accessibility? {
        guard let changed = changedAttributes else {
            return nil
        }

        return changed
    }

    public static func mockAny() -> Self {
        return .init(state: .mockAny())
    }

    public static func mockRandom() -> Self {
        return .init(state: .mockRandom())
    }
}
