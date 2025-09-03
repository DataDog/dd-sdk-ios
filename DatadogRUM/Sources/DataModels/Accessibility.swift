/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct AccessibilityInfo: Codable, Equatable {
    var textSize: String?
    var screenReaderEnabled: Bool?
    var boldTextEnabled: Bool?
    var reduceTransparencyEnabled: Bool?
    var reduceMotionEnabled: Bool?
    var buttonShapesEnabled: Bool?
    var invertColorsEnabled: Bool?
    var increaseContrastEnabled: Bool?
    var assistiveSwitchEnabled: Bool?
    var assistiveTouchEnabled: Bool?
    var videoAutoplayEnabled: Bool?
    var closedCaptioningEnabled: Bool?
    var monoAudioEnabled: Bool?
    var shakeToUndoEnabled: Bool?
    var reducedAnimationsEnabled: Bool?
    var shouldDifferentiateWithoutColor: Bool?
    var grayscaleEnabled: Bool?
    var singleAppModeEnabled: Bool?
    var onOffSwitchLabelsEnabled: Bool?
    var speakScreenEnabled: Bool?
    var speakSelectionEnabled: Bool?
    var rtlEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case textSize = "text_size"
        case screenReaderEnabled = "screen_reader_enabled"
        case boldTextEnabled = "bold_text_enabled"
        case reduceTransparencyEnabled = "reduce_transparency_enabled"
        case reduceMotionEnabled = "reduce_motion_enabled"
        case buttonShapesEnabled = "button_shapes_enabled"
        case invertColorsEnabled = "invert_colors_enabled"
        case increaseContrastEnabled = "increase_contrast_enabled"
        case assistiveSwitchEnabled = "assistive_switch_enabled"
        case assistiveTouchEnabled = "assistive_touch_enabled"
        case videoAutoplayEnabled = "video_autoplay_enabled"
        case closedCaptioningEnabled = "closed_captioning_enabled"
        case monoAudioEnabled = "mono_audio_enabled"
        case shakeToUndoEnabled = "shake_to_undo_enabled"
        case reducedAnimationsEnabled = "reduced_animations_enabled"
        case shouldDifferentiateWithoutColor = "differentiate_without_color"
        case grayscaleEnabled = "grayscale_enabled"
        case singleAppModeEnabled = "single_app_mode_enabled"
        case onOffSwitchLabelsEnabled = "on_off_switch_labels_enabled"
        case speakScreenEnabled = "speak_screen_enabled"
        case speakSelectionEnabled = "speak_selection_enabled"
        case rtlEnabled = "rtl_enabled"
    }

    static let empty = AccessibilityInfo()

    var isEmpty: Bool { self == .empty }

    /// Maps `AccessibilityInfo` to the generated RUM model.
    /// Returns `nil` when the snapshot carries no data (keeps payload lean).
    func toRUMViewAccessibility() -> RUMViewEvent.View.Accessibility? {
        if self.isEmpty {
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
    /// Returns `AccessibilityInfo.empty` when no differences are found (keeps payload lean).
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
