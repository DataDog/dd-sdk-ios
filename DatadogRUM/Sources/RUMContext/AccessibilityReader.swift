/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import UIKit

internal protocol AccessibilityReading {
    /// The current accessibility state containing all accessibility settings
    var state: AccessibilityInfo { get }
}

#if !os(watchOS)
@available(iOS 13.0, tvOS 13.0, *)
internal final class AccessibilityReader: AccessibilityReading {
    @ReadWriteLock
    private(set) var state: AccessibilityInfo

    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter) {
        self.state = AccessibilityInfo()
        self.notificationCenter = notificationCenter
        startObserving()
        updateState()
    }

    deinit {
        stopObserving()
    }

    private func updateState() {
        Task { @MainActor in
            self.state = self.currentState
        }
    }

    private func startObserving() {
        if #available(iOS 14.0, tvOS 14.0, *) {
            let buttonShapesObserver = notificationCenter.addObserver(
                forName: UIAccessibility.buttonShapesEnabledStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            }
            observers.append(buttonShapesObserver)

            let crossFadeTransitionsObserver = notificationCenter.addObserver(
                forName: UIAccessibility.prefersCrossFadeTransitionsStatusDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            }
            observers.append(crossFadeTransitionsObserver)
        }

        let videoAutoplayObserver = notificationCenter.addObserver(
            forName: UIAccessibility.videoAutoplayStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(videoAutoplayObserver)

        let differentiateWithoutColorObserver = notificationCenter.addObserver(
            forName: UIAccessibility.differentiateWithoutColorDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(differentiateWithoutColorObserver)

        let onOffSwitchLabelsObserver = notificationCenter.addObserver(
            forName: UIAccessibility.onOffSwitchLabelsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(onOffSwitchLabelsObserver)

        let voiceOverObserver = notificationCenter.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(voiceOverObserver)

        let switchControlObserver = notificationCenter.addObserver(
            forName: UIAccessibility.switchControlStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(switchControlObserver)

        let assistiveTouchObserver = notificationCenter.addObserver(
            forName: UIAccessibility.assistiveTouchStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(assistiveTouchObserver)

        let boldTextObserver = notificationCenter.addObserver(
            forName: UIAccessibility.boldTextStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(boldTextObserver)

        let closedCaptioningObserver = notificationCenter.addObserver(
            forName: UIAccessibility.closedCaptioningStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(closedCaptioningObserver)

        let reduceTransparencyObserver = notificationCenter.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(reduceTransparencyObserver)

        let reduceMotionObserver = notificationCenter.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(reduceMotionObserver)

        let invertColorsObserver = notificationCenter.addObserver(
            forName: UIAccessibility.invertColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(invertColorsObserver)

        let increaseContrastObserver = notificationCenter.addObserver(
            forName: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(increaseContrastObserver)

        let monoAudioObserver = notificationCenter.addObserver(
            forName: UIAccessibility.monoAudioStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(monoAudioObserver)

        let shakeToUndoObserver = notificationCenter.addObserver(
            forName: UIAccessibility.shakeToUndoDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(shakeToUndoObserver)

        let grayscaleObserver = notificationCenter.addObserver(
            forName: UIAccessibility.grayscaleStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(grayscaleObserver)

        let guidedAccessObserver = notificationCenter.addObserver(
            forName: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(guidedAccessObserver)

        let speakScreenObserver = notificationCenter.addObserver(
            forName: UIAccessibility.speakScreenStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(speakScreenObserver)

        let speakSelectionObserver = notificationCenter.addObserver(
            forName: UIAccessibility.speakSelectionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(speakSelectionObserver)
    }

    private func stopObserving() {
        observers.forEach { notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    @MainActor private var currentState: AccessibilityInfo {
        var state = AccessibilityInfo()

        if let contentSize = UIApplication.dd.managedShared?.preferredContentSizeCategory.rawValue as String? {
            state.textSize = contentSize
        } else {
            state.textSize = UIContentSizeCategory.unspecified.rawValue
        }

        state.videoAutoplayEnabled = UIAccessibility.isVideoAutoplayEnabled
        state.shouldDifferentiateWithoutColor = UIAccessibility.shouldDifferentiateWithoutColor
        state.onOffSwitchLabelsEnabled = UIAccessibility.isOnOffSwitchLabelsEnabled
        state.screenReaderEnabled = UIAccessibility.isVoiceOverRunning
        state.boldTextEnabled = UIAccessibility.isBoldTextEnabled
        state.reduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled
        state.reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        state.invertColorsEnabled = UIAccessibility.isInvertColorsEnabled
        state.increaseContrastEnabled = UIAccessibility.isDarkerSystemColorsEnabled
        state.assistiveSwitchEnabled = UIAccessibility.isSwitchControlRunning
        state.assistiveTouchEnabled = UIAccessibility.isAssistiveTouchRunning
        state.closedCaptioningEnabled = UIAccessibility.isClosedCaptioningEnabled
        state.monoAudioEnabled = UIAccessibility.isMonoAudioEnabled
        state.shakeToUndoEnabled = UIAccessibility.isShakeToUndoEnabled
        state.grayscaleEnabled = UIAccessibility.isGrayscaleEnabled
        state.singleAppModeEnabled = UIAccessibility.isGuidedAccessEnabled
        state.speakScreenEnabled = UIAccessibility.isSpeakScreenEnabled
        state.speakSelectionEnabled = UIAccessibility.isSpeakSelectionEnabled
        state.rtlEnabled = UIApplication.dd.managedShared?.userInterfaceLayoutDirection == .rightToLeft

        if #available(iOS 14.0, tvOS 14.0, *) {
            state.buttonShapesEnabled = UIAccessibility.buttonShapesEnabled
            state.reducedAnimationsEnabled = UIAccessibility.prefersCrossFadeTransitions
        }

        return state
    }
}
#else
// No-op implementation for watchOS where UIAccessibility APIs are unavailable
internal final class AccessibilityReader: AccessibilityReading {
    var state: AccessibilityInfo {
        return AccessibilityInfo()
    }
    
    init(notificationCenter: NotificationCenter) {
        // No-op on watchOS
    }
}
#endif
