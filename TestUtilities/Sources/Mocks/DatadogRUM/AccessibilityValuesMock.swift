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

    public init(state: AccessibilityInfo = .mockAny()) {
        self.state = state
    }

    public static func mockAny() -> Self {
        return .init(state: .mockAny())
    }

    public static func mockRandom() -> Self {
        return .init(state: .mockRandom())
    }
}
