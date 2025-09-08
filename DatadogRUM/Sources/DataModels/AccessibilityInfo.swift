/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct AccessibilityInfo: Equatable {
    var textSize: String? { didSet { hasAccessibilityData = true } }
    var screenReaderEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var boldTextEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var reduceTransparencyEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var reduceMotionEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var buttonShapesEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var invertColorsEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var increaseContrastEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var assistiveSwitchEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var assistiveTouchEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var videoAutoplayEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var closedCaptioningEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var monoAudioEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var shakeToUndoEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var reducedAnimationsEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var shouldDifferentiateWithoutColor: Bool? { didSet { hasAccessibilityData = true } }
    var grayscaleEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var singleAppModeEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var onOffSwitchLabelsEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var speakScreenEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var speakSelectionEnabled: Bool? { didSet { hasAccessibilityData = true } }
    var rtlEnabled: Bool? { didSet { hasAccessibilityData = true } }

    private(set) var hasAccessibilityData = false

    init(
        textSize: String? = nil,
        screenReaderEnabled: Bool? = nil,
        boldTextEnabled: Bool? = nil,
        reduceTransparencyEnabled: Bool? = nil,
        reduceMotionEnabled: Bool? = nil,
        buttonShapesEnabled: Bool? = nil,
        invertColorsEnabled: Bool? = nil,
        increaseContrastEnabled: Bool? = nil,
        assistiveSwitchEnabled: Bool? = nil,
        assistiveTouchEnabled: Bool? = nil,
        videoAutoplayEnabled: Bool? = nil,
        closedCaptioningEnabled: Bool? = nil,
        monoAudioEnabled: Bool? = nil,
        shakeToUndoEnabled: Bool? = nil,
        reducedAnimationsEnabled: Bool? = nil,
        shouldDifferentiateWithoutColor: Bool? = nil,
        grayscaleEnabled: Bool? = nil,
        singleAppModeEnabled: Bool? = nil,
        onOffSwitchLabelsEnabled: Bool? = nil,
        speakScreenEnabled: Bool? = nil,
        speakSelectionEnabled: Bool? = nil,
        rtlEnabled: Bool? = nil
    ) {
        self.textSize = textSize
        self.screenReaderEnabled = screenReaderEnabled
        self.boldTextEnabled = boldTextEnabled
        self.reduceTransparencyEnabled = reduceTransparencyEnabled
        self.reduceMotionEnabled = reduceMotionEnabled
        self.buttonShapesEnabled = buttonShapesEnabled
        self.invertColorsEnabled = invertColorsEnabled
        self.increaseContrastEnabled = increaseContrastEnabled
        self.assistiveSwitchEnabled = assistiveSwitchEnabled
        self.assistiveTouchEnabled = assistiveTouchEnabled
        self.videoAutoplayEnabled = videoAutoplayEnabled
        self.closedCaptioningEnabled = closedCaptioningEnabled
        self.monoAudioEnabled = monoAudioEnabled
        self.shakeToUndoEnabled = shakeToUndoEnabled
        self.reducedAnimationsEnabled = reducedAnimationsEnabled
        self.shouldDifferentiateWithoutColor = shouldDifferentiateWithoutColor
        self.grayscaleEnabled = grayscaleEnabled
        self.singleAppModeEnabled = singleAppModeEnabled
        self.onOffSwitchLabelsEnabled = onOffSwitchLabelsEnabled
        self.speakScreenEnabled = speakScreenEnabled
        self.speakSelectionEnabled = speakSelectionEnabled
        self.rtlEnabled = rtlEnabled

        // Set hasAccessibilityData to true if any value is not nil
        self.hasAccessibilityData = textSize != nil ||
                                   screenReaderEnabled != nil ||
                                   boldTextEnabled != nil ||
                                   reduceTransparencyEnabled != nil ||
                                   reduceMotionEnabled != nil ||
                                   buttonShapesEnabled != nil ||
                                   invertColorsEnabled != nil ||
                                   increaseContrastEnabled != nil ||
                                   assistiveSwitchEnabled != nil ||
                                   assistiveTouchEnabled != nil ||
                                   videoAutoplayEnabled != nil ||
                                   closedCaptioningEnabled != nil ||
                                   monoAudioEnabled != nil ||
                                   shakeToUndoEnabled != nil ||
                                   reducedAnimationsEnabled != nil ||
                                   shouldDifferentiateWithoutColor != nil ||
                                   grayscaleEnabled != nil ||
                                   singleAppModeEnabled != nil ||
                                   onOffSwitchLabelsEnabled != nil ||
                                   speakScreenEnabled != nil ||
                                   speakSelectionEnabled != nil ||
                                   rtlEnabled != nil
    }

    /// Maps `AccessibilityInfo` to the generated RUM model.
    /// Returns `nil` when the snapshot carries no data (keeps payload lean).
    var rumViewAccessibility: RUMViewEvent.View.Accessibility? {
        if !self.hasAccessibilityData {
            return nil
        }

        return RUMViewEvent.View.Accessibility(
            assistiveSwitchEnabled: self.assistiveSwitchEnabled,
            assistiveTouchEnabled: self.assistiveTouchEnabled,
            boldTextEnabled: self.boldTextEnabled,
            buttonShapesEnabled: self.buttonShapesEnabled,
            closedCaptioningEnabled: self.closedCaptioningEnabled,
            grayscaleEnabled: self.grayscaleEnabled,
            increaseContrastEnabled: self.increaseContrastEnabled,
            invertColorsEnabled: self.invertColorsEnabled,
            monoAudioEnabled: self.monoAudioEnabled,
            onOffSwitchLabelsEnabled: self.onOffSwitchLabelsEnabled,
            reduceMotionEnabled: self.reduceMotionEnabled,
            reduceTransparencyEnabled: self.reduceTransparencyEnabled,
            reducedAnimationsEnabled: self.reducedAnimationsEnabled,
            rtlEnabled: self.rtlEnabled,
            screenReaderEnabled: self.screenReaderEnabled,
            shakeToUndoEnabled: self.shakeToUndoEnabled,
            shouldDifferentiateWithoutColor: self.shouldDifferentiateWithoutColor,
            singleAppModeEnabled: self.singleAppModeEnabled,
            speakScreenEnabled: self.speakScreenEnabled,
            speakSelectionEnabled: self.speakSelectionEnabled,
            textSize: self.textSize,
            videoAutoplayEnabled: self.videoAutoplayEnabled
        )
    }

    /// Compares this `AccessibilityInfo` with another and returns only the differing values.
    /// Returns an instance with `hasAccessibilityData = false` when no differences are found (keeps payload lean).
    /// If `other` is `nil`, returns the current state as all values are considered different from no previous state.
    func differences(from other: AccessibilityInfo?) -> AccessibilityInfo {
        // If there's no previous state to compare against, return current state as difference
        guard let other = other else {
            return self
        }

        var differences = AccessibilityInfo()

        // Compare each property and include only if different
        if self.textSize != other.textSize {
            differences.textSize = self.textSize
        }
        if self.screenReaderEnabled != other.screenReaderEnabled {
            differences.screenReaderEnabled = self.screenReaderEnabled
        }
        if self.boldTextEnabled != other.boldTextEnabled {
            differences.boldTextEnabled = self.boldTextEnabled
        }
        if self.reduceTransparencyEnabled != other.reduceTransparencyEnabled {
            differences.reduceTransparencyEnabled = self.reduceTransparencyEnabled
        }
        if self.reduceMotionEnabled != other.reduceMotionEnabled {
            differences.reduceMotionEnabled = self.reduceMotionEnabled
        }
        if self.buttonShapesEnabled != other.buttonShapesEnabled {
            differences.buttonShapesEnabled = self.buttonShapesEnabled
        }
        if self.invertColorsEnabled != other.invertColorsEnabled {
            differences.invertColorsEnabled = self.invertColorsEnabled
        }
        if self.increaseContrastEnabled != other.increaseContrastEnabled {
            differences.increaseContrastEnabled = self.increaseContrastEnabled
        }
        if self.assistiveSwitchEnabled != other.assistiveSwitchEnabled {
            differences.assistiveSwitchEnabled = self.assistiveSwitchEnabled
        }
        if self.assistiveTouchEnabled != other.assistiveTouchEnabled {
            differences.assistiveTouchEnabled = self.assistiveTouchEnabled
        }
        if self.videoAutoplayEnabled != other.videoAutoplayEnabled {
            differences.videoAutoplayEnabled = self.videoAutoplayEnabled
        }
        if self.closedCaptioningEnabled != other.closedCaptioningEnabled {
            differences.closedCaptioningEnabled = self.closedCaptioningEnabled
        }
        if self.monoAudioEnabled != other.monoAudioEnabled {
            differences.monoAudioEnabled = self.monoAudioEnabled
        }
        if self.shakeToUndoEnabled != other.shakeToUndoEnabled {
            differences.shakeToUndoEnabled = self.shakeToUndoEnabled
        }
        if self.reducedAnimationsEnabled != other.reducedAnimationsEnabled {
            differences.reducedAnimationsEnabled = self.reducedAnimationsEnabled
        }
        if self.shouldDifferentiateWithoutColor != other.shouldDifferentiateWithoutColor {
            differences.shouldDifferentiateWithoutColor = self.shouldDifferentiateWithoutColor
        }
        if self.grayscaleEnabled != other.grayscaleEnabled {
            differences.grayscaleEnabled = self.grayscaleEnabled
        }
        if self.singleAppModeEnabled != other.singleAppModeEnabled {
            differences.singleAppModeEnabled = self.singleAppModeEnabled
        }
        if self.onOffSwitchLabelsEnabled != other.onOffSwitchLabelsEnabled {
            differences.onOffSwitchLabelsEnabled = self.onOffSwitchLabelsEnabled
        }
        if self.speakScreenEnabled != other.speakScreenEnabled {
            differences.speakScreenEnabled = self.speakScreenEnabled
        }
        if self.speakSelectionEnabled != other.speakSelectionEnabled {
            differences.speakSelectionEnabled = self.speakSelectionEnabled
        }
        if self.rtlEnabled != other.rtlEnabled {
            differences.rtlEnabled = self.rtlEnabled
        }

        return differences
    }
}
