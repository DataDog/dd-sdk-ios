/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import UIKit

internal final class AccessibilityReader {
    @ReadWriteLock
    private(set) var state: Accessibility

    private let notificationCenter: NotificationCenter
    private let accessibilityValues: AccessibilityValues
    private var observers: [NSObjectProtocol] = []

    @available(iOS 13.0, tvOS 13.0, *)
    init(
        notificationCenter: NotificationCenter,
        accessibilityValues: AccessibilityValues = LiveAccessibilityValues()
    ) {
        self.state = Accessibility()
        self.notificationCenter = notificationCenter
        self.accessibilityValues = accessibilityValues
        startObserving()
        updateState()
    }

    deinit {
        stopObserving()
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func updateState() {
        Task { @MainActor in
            self.state = self.currentState
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
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

    @MainActor private var currentState: Accessibility {
        var state = Accessibility()

        state.textSize = accessibilityValues.textSize
        state.videoAutoplayEnabled = accessibilityValues.isVideoAutoplayEnabled
        state.shouldDifferentiateWithoutColor = accessibilityValues.shouldDifferentiateWithoutColor
        state.onOffSwitchLabelsEnabled = accessibilityValues.isOnOffSwitchLabelsEnabled
        state.buttonShapesEnabled = accessibilityValues.buttonShapesEnabled
        state.reducedAnimationsEnabled = accessibilityValues.prefersCrossFadeTransitions
        state.screenReaderEnabled = accessibilityValues.isVoiceOverRunning
        state.boldTextEnabled = accessibilityValues.isBoldTextEnabled
        state.reduceTransparencyEnabled = accessibilityValues.isReduceTransparencyEnabled
        state.reduceMotionEnabled = accessibilityValues.isReduceMotionEnabled
        state.invertColorsEnabled = accessibilityValues.isInvertColorsEnabled
        state.increaseContrastEnabled = accessibilityValues.isDarkerSystemColorsEnabled
        state.assistiveSwitchEnabled = accessibilityValues.isSwitchControlRunning
        state.assistiveTouchEnabled = accessibilityValues.isAssistiveTouchRunning
        state.closedCaptioningEnabled = accessibilityValues.isClosedCaptioningEnabled
        state.monoAudioEnabled = accessibilityValues.isMonoAudioEnabled
        state.shakeToUndoEnabled = accessibilityValues.isShakeToUndoEnabled
        state.grayscaleEnabled = accessibilityValues.isGrayscaleEnabled
        state.singleAppModeEnabled = accessibilityValues.isGuidedAccessEnabled
        state.speakScreenEnabled = accessibilityValues.isSpeakScreenEnabled
        state.speakSelectionEnabled = accessibilityValues.isSpeakSelectionEnabled
        state.rtlEnabled = accessibilityValues.rtlEnabled

        return state
    }
}
