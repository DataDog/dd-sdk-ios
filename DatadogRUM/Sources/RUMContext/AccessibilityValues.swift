/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal protocol AccessibilityValues: AnyObject {
    @MainActor var isVideoAutoplayEnabled: Bool? { get }
    @MainActor var shouldDifferentiateWithoutColor: Bool? { get }
    @MainActor var isOnOffSwitchLabelsEnabled: Bool? { get }
    @MainActor var buttonShapesEnabled: Bool? { get }
    @MainActor var prefersCrossFadeTransitions: Bool? { get }
    @MainActor var isVoiceOverRunning: Bool { get }
    @MainActor var isMonoAudioEnabled: Bool { get }
    @MainActor var isClosedCaptioningEnabled: Bool { get }
    @MainActor var isInvertColorsEnabled: Bool { get }
    @MainActor var isGuidedAccessEnabled: Bool { get }
    @MainActor var isBoldTextEnabled: Bool { get }
    @MainActor var isGrayscaleEnabled: Bool { get }
    @MainActor var isReduceTransparencyEnabled: Bool { get }
    @MainActor var isReduceMotionEnabled: Bool { get }
    @MainActor var isDarkerSystemColorsEnabled: Bool { get }
    @MainActor var isSwitchControlRunning: Bool { get }
    @MainActor var isSpeakSelectionEnabled: Bool { get }
    @MainActor var isSpeakScreenEnabled: Bool { get }
    @MainActor var isShakeToUndoEnabled: Bool { get }
    @MainActor var isAssistiveTouchRunning: Bool { get }
    @MainActor var rtlEnabled: Bool { get }
    @MainActor var textSize: String { get }
}

internal final class LiveAccessibilityValues: AccessibilityValues {
    init() {
    }

    @MainActor var isVideoAutoplayEnabled: Bool? {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return UIAccessibility.isVideoAutoplayEnabled
        } else {
            return nil
        }
    }

    @MainActor var shouldDifferentiateWithoutColor: Bool? {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return UIAccessibility.shouldDifferentiateWithoutColor
        } else {
            return nil
        }
    }

    @MainActor var isOnOffSwitchLabelsEnabled: Bool? {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return UIAccessibility.isOnOffSwitchLabelsEnabled
        } else {
            return nil
        }
    }

    @MainActor var buttonShapesEnabled: Bool? {
        if #available(iOS 14.0, tvOS 14.0, *) {
            return UIAccessibility.buttonShapesEnabled
        } else {
            return nil
        }
    }

    @MainActor var prefersCrossFadeTransitions: Bool? {
        if #available(iOS 14.0, tvOS 14.0, *) {
            return UIAccessibility.prefersCrossFadeTransitions
        } else {
            return nil
        }
    }

    @MainActor var isVoiceOverRunning: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    @MainActor var isMonoAudioEnabled: Bool {
        UIAccessibility.isMonoAudioEnabled
    }

    @MainActor var isClosedCaptioningEnabled: Bool {
        UIAccessibility.isClosedCaptioningEnabled
    }

    @MainActor var isInvertColorsEnabled: Bool {
        UIAccessibility.isInvertColorsEnabled
    }

    @MainActor var isGuidedAccessEnabled: Bool {
        UIAccessibility.isGuidedAccessEnabled
    }

    @MainActor var isBoldTextEnabled: Bool {
        UIAccessibility.isBoldTextEnabled
    }

    @MainActor var isGrayscaleEnabled: Bool {
        UIAccessibility.isGrayscaleEnabled
    }

    @MainActor var isReduceTransparencyEnabled: Bool {
        UIAccessibility.isReduceTransparencyEnabled
    }

    @MainActor var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    @MainActor var isDarkerSystemColorsEnabled: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled
    }

    @MainActor var isSwitchControlRunning: Bool {
        UIAccessibility.isSwitchControlRunning
    }

    @MainActor var isSpeakSelectionEnabled: Bool {
        UIAccessibility.isSpeakSelectionEnabled
    }

    @MainActor var isSpeakScreenEnabled: Bool {
        UIAccessibility.isSpeakScreenEnabled
    }

    @MainActor var isShakeToUndoEnabled: Bool {
        UIAccessibility.isShakeToUndoEnabled
    }

    @MainActor var isAssistiveTouchRunning: Bool {
        UIAccessibility.isAssistiveTouchRunning
    }

    @MainActor var rtlEnabled: Bool {
        UIApplication.dd.managedShared?.userInterfaceLayoutDirection == .rightToLeft
    }

    @MainActor var textSize: String {
        UIApplication.dd.managedShared?.preferredContentSizeCategory.rawValue as String? ?? ""
    }
}
