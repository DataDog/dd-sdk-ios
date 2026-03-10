/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal protocol AccessibilityReading {
    /// The current accessibility state containing all accessibility settings
    var state: AccessibilityInfo { get }
}

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
        #if canImport(UIKit)
        if #available(iOS 14.0, tvOS 14.0, *) {
            let buttonShapesObserver = notificationCenter.addObserver(
                forName: DDAccessibility.buttonShapesEnabledStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            }
            observers.append(buttonShapesObserver)

            let crossFadeTransitionsObserver = notificationCenter.addObserver(
                forName: DDAccessibility.prefersCrossFadeTransitionsStatusDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            }
            observers.append(crossFadeTransitionsObserver)
        }

        let videoAutoplayObserver = notificationCenter.addObserver(
            forName: DDAccessibility.videoAutoplayStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(videoAutoplayObserver)

        let differentiateWithoutColorObserver = notificationCenter.addObserver(
            forName: DDAccessibility.differentiateWithoutColorDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(differentiateWithoutColorObserver)

        let onOffSwitchLabelsObserver = notificationCenter.addObserver(
            forName: DDAccessibility.onOffSwitchLabelsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(onOffSwitchLabelsObserver)

        let voiceOverObserver = notificationCenter.addObserver(
            forName: DDAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(voiceOverObserver)

        let switchControlObserver = notificationCenter.addObserver(
            forName: DDAccessibility.switchControlStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(switchControlObserver)

        let assistiveTouchObserver = notificationCenter.addObserver(
            forName: DDAccessibility.assistiveTouchStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(assistiveTouchObserver)

        let boldTextObserver = notificationCenter.addObserver(
            forName: DDAccessibility.boldTextStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(boldTextObserver)

        let closedCaptioningObserver = notificationCenter.addObserver(
            forName: DDAccessibility.closedCaptioningStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(closedCaptioningObserver)

        let reduceTransparencyObserver = notificationCenter.addObserver(
            forName: DDAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(reduceTransparencyObserver)

        let reduceMotionObserver = notificationCenter.addObserver(
            forName: DDAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(reduceMotionObserver)

        let invertColorsObserver = notificationCenter.addObserver(
            forName: DDAccessibility.invertColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(invertColorsObserver)

        let increaseContrastObserver = notificationCenter.addObserver(
            forName: DDAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(increaseContrastObserver)

        let monoAudioObserver = notificationCenter.addObserver(
            forName: DDAccessibility.monoAudioStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(monoAudioObserver)

        let shakeToUndoObserver = notificationCenter.addObserver(
            forName: DDAccessibility.shakeToUndoDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(shakeToUndoObserver)

        let grayscaleObserver = notificationCenter.addObserver(
            forName: DDAccessibility.grayscaleStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(grayscaleObserver)

        let guidedAccessObserver = notificationCenter.addObserver(
            forName: DDAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(guidedAccessObserver)

        let speakScreenObserver = notificationCenter.addObserver(
            forName: DDAccessibility.speakScreenStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(speakScreenObserver)

        let speakSelectionObserver = notificationCenter.addObserver(
            forName: DDAccessibility.speakSelectionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(speakSelectionObserver)
        #endif
    }

    private func stopObserving() {
        observers.forEach { notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    @MainActor private var currentState: AccessibilityInfo {
        var state = AccessibilityInfo()

        #if canImport(UIKit)
        if let contentSize = UIApplication.dd.managedShared?.preferredContentSizeCategory.rawValue as String? {
            state.textSize = contentSize
        } else {
            state.textSize = UIContentSizeCategory.unspecified.rawValue
        }

        state.videoAutoplayEnabled = DDAccessibility.isVideoAutoplayEnabled
        state.shouldDifferentiateWithoutColor = DDAccessibility.shouldDifferentiateWithoutColor
        state.onOffSwitchLabelsEnabled = DDAccessibility.isOnOffSwitchLabelsEnabled
        state.screenReaderEnabled = DDAccessibility.isVoiceOverRunning
        state.boldTextEnabled = DDAccessibility.isBoldTextEnabled
        state.reduceTransparencyEnabled = DDAccessibility.isReduceTransparencyEnabled
        state.reduceMotionEnabled = DDAccessibility.isReduceMotionEnabled
        state.invertColorsEnabled = DDAccessibility.isInvertColorsEnabled
        state.increaseContrastEnabled = DDAccessibility.isDarkerSystemColorsEnabled
        state.assistiveSwitchEnabled = DDAccessibility.isSwitchControlRunning
        state.assistiveTouchEnabled = DDAccessibility.isAssistiveTouchRunning
        state.closedCaptioningEnabled = DDAccessibility.isClosedCaptioningEnabled
        state.monoAudioEnabled = DDAccessibility.isMonoAudioEnabled
        state.shakeToUndoEnabled = DDAccessibility.isShakeToUndoEnabled
        state.grayscaleEnabled = DDAccessibility.isGrayscaleEnabled
        state.singleAppModeEnabled = DDAccessibility.isGuidedAccessEnabled
        state.speakScreenEnabled = DDAccessibility.isSpeakScreenEnabled
        state.speakSelectionEnabled = DDAccessibility.isSpeakSelectionEnabled
        state.rtlEnabled = UIApplication.dd.managedShared?.userInterfaceLayoutDirection == .rightToLeft

        if #available(iOS 14.0, tvOS 14.0, *) {
            state.buttonShapesEnabled = DDAccessibility.buttonShapesEnabled
            state.reducedAnimationsEnabled = DDAccessibility.prefersCrossFadeTransitions
        }
        #endif

        return state
    }
}
