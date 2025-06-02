/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogRUM

public final class AccessibilityValuesMock: AccessibilityValues, AnyMockable, RandomMockable {
    init(isVideoAutoplayEnabled: Bool? = false,
         shouldDifferentiateWithoutColor: Bool? = false,
         isOnOffSwitchLabelsEnabled: Bool? = false,
         buttonShapesEnabled: Bool? = false,
         prefersCrossFadeTransitions: Bool? = false,
         isVoiceOverRunning: Bool = false,
         isMonoAudioEnabled: Bool = false,
         isClosedCaptioningEnabled: Bool = false,
         isInvertColorsEnabled: Bool = false,
         isGuidedAccessEnabled: Bool = false,
         isBoldTextEnabled: Bool = false,
         isGrayscaleEnabled: Bool = false,
         isReduceTransparencyEnabled: Bool = false,
         isReduceMotionEnabled: Bool = false,
         isDarkerSystemColorsEnabled: Bool = false,
         isSwitchControlRunning: Bool = false,
         isSpeakSelectionEnabled: Bool = false,
         isSpeakScreenEnabled: Bool = false,
         isShakeToUndoEnabled: Bool = false,
         isAssistiveTouchRunning: Bool = false,
         rtlEnabled: Bool = false,
         textSize: String = "medium"
    ) {
        self.isVideoAutoplayEnabled = isVideoAutoplayEnabled
        self.shouldDifferentiateWithoutColor = shouldDifferentiateWithoutColor
        self.isOnOffSwitchLabelsEnabled = isOnOffSwitchLabelsEnabled
        self.buttonShapesEnabled = buttonShapesEnabled
        self.prefersCrossFadeTransitions = prefersCrossFadeTransitions
        self.isVoiceOverRunning = isVoiceOverRunning
        self.isMonoAudioEnabled = isMonoAudioEnabled
        self.isClosedCaptioningEnabled = isClosedCaptioningEnabled
        self.isInvertColorsEnabled = isInvertColorsEnabled
        self.isGuidedAccessEnabled = isGuidedAccessEnabled
        self.isBoldTextEnabled = isBoldTextEnabled
        self.isGrayscaleEnabled = isGrayscaleEnabled
        self.isReduceTransparencyEnabled = isReduceTransparencyEnabled
        self.isReduceMotionEnabled = isReduceMotionEnabled
        self.isDarkerSystemColorsEnabled = isDarkerSystemColorsEnabled
        self.isSwitchControlRunning = isSwitchControlRunning
        self.isSpeakSelectionEnabled = isSpeakSelectionEnabled
        self.isSpeakScreenEnabled = isSpeakScreenEnabled
        self.isShakeToUndoEnabled = isShakeToUndoEnabled
        self.isAssistiveTouchRunning = isAssistiveTouchRunning
        self.rtlEnabled = rtlEnabled
        self.textSize = textSize
    }

    @MainActor public var isVideoAutoplayEnabled: Bool?
    @MainActor public var shouldDifferentiateWithoutColor: Bool?
    @MainActor public var isOnOffSwitchLabelsEnabled: Bool?
    @MainActor public var buttonShapesEnabled: Bool?
    @MainActor public var prefersCrossFadeTransitions: Bool?
    @MainActor public var isVoiceOverRunning: Bool
    @MainActor public var isMonoAudioEnabled: Bool
    @MainActor public var isClosedCaptioningEnabled: Bool
    @MainActor public var isInvertColorsEnabled: Bool
    @MainActor public var isGuidedAccessEnabled: Bool
    @MainActor public var isBoldTextEnabled: Bool
    @MainActor public var isGrayscaleEnabled: Bool
    @MainActor public var isReduceTransparencyEnabled: Bool
    @MainActor public var isReduceMotionEnabled: Bool
    @MainActor public var isDarkerSystemColorsEnabled: Bool
    @MainActor public var isSwitchControlRunning: Bool
    @MainActor public var isSpeakSelectionEnabled: Bool
    @MainActor public var isSpeakScreenEnabled: Bool
    @MainActor public var isShakeToUndoEnabled: Bool
    @MainActor public var isAssistiveTouchRunning: Bool
    @MainActor public var rtlEnabled: Bool
    @MainActor public var textSize: String

    public static func mockAny() -> Self {
        .init(isVideoAutoplayEnabled: .mockAny(), shouldDifferentiateWithoutColor: .mockAny(), isOnOffSwitchLabelsEnabled: .mockAny(), buttonShapesEnabled: .mockAny(), prefersCrossFadeTransitions: .mockAny(), isVoiceOverRunning: .mockAny(), isMonoAudioEnabled: .mockAny(), isClosedCaptioningEnabled: .mockAny(), isInvertColorsEnabled: .mockAny(), isGuidedAccessEnabled: .mockAny(), isBoldTextEnabled: .mockAny(), isGrayscaleEnabled: .mockAny(), isReduceTransparencyEnabled: .mockAny(), isReduceMotionEnabled: .mockAny(), isDarkerSystemColorsEnabled: .mockAny(), isSwitchControlRunning: .mockAny(), isSpeakSelectionEnabled: .mockAny(), isSpeakScreenEnabled: .mockAny(), isShakeToUndoEnabled: .mockAny(), isAssistiveTouchRunning: .mockAny(), rtlEnabled: .mockAny(), textSize: .mockAny())
    }

    public static func mockRandom() -> Self {
        .init(
            isVideoAutoplayEnabled: .random(),
            shouldDifferentiateWithoutColor: .random(),
            isOnOffSwitchLabelsEnabled: .random(),
            buttonShapesEnabled: .random(),
            prefersCrossFadeTransitions: .random(),
            isVoiceOverRunning: .random(),
            isMonoAudioEnabled: .random(),
            isClosedCaptioningEnabled: .random(),
            isInvertColorsEnabled: .random(),
            isGuidedAccessEnabled: .random(),
            isBoldTextEnabled: .random(),
            isGrayscaleEnabled: .random(),
            isReduceTransparencyEnabled: .random(),
            isReduceMotionEnabled: .random(),
            isDarkerSystemColorsEnabled: .random(),
            isSwitchControlRunning: .random(),
            isSpeakSelectionEnabled: .random(),
            isSpeakScreenEnabled: .random(),
            isShakeToUndoEnabled: .random(),
            isAssistiveTouchRunning: .random(),
            rtlEnabled: .random(),
            textSize: "medium"
        )
    }
}
