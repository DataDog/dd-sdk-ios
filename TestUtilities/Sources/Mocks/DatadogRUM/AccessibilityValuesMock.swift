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
    private var isFirstViewUpdate = true
    private var changedAttributes: [String: Any] = [:]

    public init(state: AccessibilityInfo = .mockAny()) {
        self.state = state
    }

    /// Converts the current accessibility state to RUM View Event accessibility format
    public var rumAccessibility: RUMViewEvent.View.Accessibility? {
        // Only proceed if we have a valid state (at least one non-nil value)
        guard hasValidAccessibilityData else {
            return nil
        }

        if isFirstViewUpdate {
            // First view update: return all accessibility attributes
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
        } else {
            // Subsequent updates: only return changed attributes
            return createAccessibilityFromChangedAttributes()
        }
    }

    /// Called after a view update event has been sent to clear the changed attributes
    public func clearChangedAttributes() {
        changedAttributes.removeAll()

        if isFirstViewUpdate {
            isFirstViewUpdate = false
        }
    }

    /// Reset for a new view - should be called when a new view starts
    public func resetForNewView() {
        isFirstViewUpdate = true
        changedAttributes.removeAll()
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
        if !isFirstViewUpdate {
            // Track changes for all attributes
            if state.assistiveSwitchEnabled != newState.assistiveSwitchEnabled {
                changedAttributes["assistiveSwitchEnabled"] = newState.assistiveSwitchEnabled
            }
            if state.assistiveTouchEnabled != newState.assistiveTouchEnabled {
                changedAttributes["assistiveTouchEnabled"] = newState.assistiveTouchEnabled
            }
            if state.boldTextEnabled != newState.boldTextEnabled {
                changedAttributes["boldTextEnabled"] = newState.boldTextEnabled
            }
            if state.buttonShapesEnabled != newState.buttonShapesEnabled {
                changedAttributes["buttonShapesEnabled"] = newState.buttonShapesEnabled
            }
            if state.closedCaptioningEnabled != newState.closedCaptioningEnabled {
                changedAttributes["closedCaptioningEnabled"] = newState.closedCaptioningEnabled
            }
            if state.grayscaleEnabled != newState.grayscaleEnabled {
                changedAttributes["grayscaleEnabled"] = newState.grayscaleEnabled
            }
            if state.increaseContrastEnabled != newState.increaseContrastEnabled {
                changedAttributes["increaseContrastEnabled"] = newState.increaseContrastEnabled
            }
            if state.invertColorsEnabled != newState.invertColorsEnabled {
                changedAttributes["invertColorsEnabled"] = newState.invertColorsEnabled
            }
            if state.monoAudioEnabled != newState.monoAudioEnabled {
                changedAttributes["monoAudioEnabled"] = newState.monoAudioEnabled
            }
            if state.onOffSwitchLabelsEnabled != newState.onOffSwitchLabelsEnabled {
                changedAttributes["onOffSwitchLabelsEnabled"] = newState.onOffSwitchLabelsEnabled
            }
            if state.reduceMotionEnabled != newState.reduceMotionEnabled {
                changedAttributes["reduceMotionEnabled"] = newState.reduceMotionEnabled
            }
            if state.reduceTransparencyEnabled != newState.reduceTransparencyEnabled {
                changedAttributes["reduceTransparencyEnabled"] = newState.reduceTransparencyEnabled
            }
            if state.reducedAnimationsEnabled != newState.reducedAnimationsEnabled {
                changedAttributes["reducedAnimationsEnabled"] = newState.reducedAnimationsEnabled
            }
            if state.screenReaderEnabled != newState.screenReaderEnabled {
                changedAttributes["screenReaderEnabled"] = newState.screenReaderEnabled
            }
            if state.shakeToUndoEnabled != newState.shakeToUndoEnabled {
                changedAttributes["shakeToUndoEnabled"] = newState.shakeToUndoEnabled
            }
            if state.shouldDifferentiateWithoutColor != newState.shouldDifferentiateWithoutColor {
                changedAttributes["shouldDifferentiateWithoutColor"] = newState.shouldDifferentiateWithoutColor
            }
            if state.singleAppModeEnabled != newState.singleAppModeEnabled {
                changedAttributes["singleAppModeEnabled"] = newState.singleAppModeEnabled
            }
            if state.speakScreenEnabled != newState.speakScreenEnabled {
                changedAttributes["speakScreenEnabled"] = newState.speakScreenEnabled
            }
            if state.speakSelectionEnabled != newState.speakSelectionEnabled {
                changedAttributes["speakSelectionEnabled"] = newState.speakSelectionEnabled
            }
            if state.textSize != newState.textSize {
                changedAttributes["textSize"] = newState.textSize
            }
            if state.videoAutoplayEnabled != newState.videoAutoplayEnabled {
                changedAttributes["videoAutoplayEnabled"] = newState.videoAutoplayEnabled
            }
            if state.rtlEnabled != newState.rtlEnabled {
                changedAttributes["rtlEnabled"] = newState.rtlEnabled
            }
        }
        state = newState
    }

    /// Create accessibility object from changed attributes only
    private func createAccessibilityFromChangedAttributes() -> RUMViewEvent.View.Accessibility? {
        guard !changedAttributes.isEmpty else {
            return nil
        }

        return RUMViewEvent.View.Accessibility(
            assistiveSwitchEnabled: changedAttributes["assistiveSwitchEnabled"] as? Bool,
            assistiveTouchEnabled: changedAttributes["assistiveTouchEnabled"] as? Bool,
            boldTextEnabled: changedAttributes["boldTextEnabled"] as? Bool,
            buttonShapesEnabled: changedAttributes["buttonShapesEnabled"] as? Bool,
            closedCaptioningEnabled: changedAttributes["closedCaptioningEnabled"] as? Bool,
            grayscaleEnabled: changedAttributes["grayscaleEnabled"] as? Bool,
            increaseContrastEnabled: changedAttributes["increaseContrastEnabled"] as? Bool,
            invertColorsEnabled: changedAttributes["invertColorsEnabled"] as? Bool,
            monoAudioEnabled: changedAttributes["monoAudioEnabled"] as? Bool,
            onOffSwitchLabelsEnabled: changedAttributes["onOffSwitchLabelsEnabled"] as? Bool,
            reduceMotionEnabled: changedAttributes["reduceMotionEnabled"] as? Bool,
            reduceTransparencyEnabled: changedAttributes["reduceTransparencyEnabled"] as? Bool,
            reducedAnimationsEnabled: changedAttributes["reducedAnimationsEnabled"] as? Bool,
            rtlEnabled: changedAttributes["rtlEnabled"] as? Bool,
            screenReaderEnabled: changedAttributes["screenReaderEnabled"] as? Bool,
            shakeToUndoEnabled: changedAttributes["shakeToUndoEnabled"] as? Bool,
            shouldDifferentiateWithoutColor: changedAttributes["shouldDifferentiateWithoutColor"] as? Bool,
            singleAppModeEnabled: changedAttributes["singleAppModeEnabled"] as? Bool,
            speakScreenEnabled: changedAttributes["speakScreenEnabled"] as? Bool,
            speakSelectionEnabled: changedAttributes["speakSelectionEnabled"] as? Bool,
            textSize: changedAttributes["textSize"] as? String,
            videoAutoplayEnabled: changedAttributes["videoAutoplayEnabled"] as? Bool
        )
    }

    public static func mockAny() -> Self {
        return .init(state: .mockAny())
    }

    public static func mockRandom() -> Self {
        return .init(state: .mockRandom())
    }
}
