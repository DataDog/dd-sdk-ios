/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogRUM

internal final class MockAccessibilityValues: AccessibilityValues {
    var isVideoAutoplayEnabled: Bool = false
    var shouldDifferentiateWithoutColor: Bool = false
    var isOnOffSwitchLabelsEnabled: Bool = false
    var buttonShapesEnabled: Bool = false
    var prefersCrossFadeTransitions: Bool = false
    var isVoiceOverRunning: Bool = false
    var isMonoAudioEnabled: Bool = false
    var isClosedCaptioningEnabled: Bool = false
    var isInvertColorsEnabled: Bool = false
    var isGuidedAccessEnabled: Bool = false
    var isBoldTextEnabled: Bool = false
    var isGrayscaleEnabled: Bool = false
    var isReduceTransparencyEnabled: Bool = false
    var isReduceMotionEnabled: Bool = false
    var isDarkerSystemColorsEnabled: Bool = false
    var isSwitchControlRunning: Bool = false
    var isSpeakSelectionEnabled: Bool = false
    var isSpeakScreenEnabled: Bool = false
    var isShakeToUndoEnabled: Bool = false
    var isAssistiveTouchRunning: Bool = false
    var rtlEnabled: Bool = false
    var textSize: String = ""
}
