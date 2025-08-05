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

    /// Converts the current accessibility state to RUM View Event accessibility format.
    /// Returns all accessibility attributes on the first view update, or only changed attributes on subsequent updates.
    /// Returns nil if no valid accessibility data is available.
    var rumAccessibility: RUMViewEvent.View.Accessibility? { get }

    /// Indicates whether the current accessibility state contains valid data to send.
    /// Returns true if at least one accessibility property has a non-nil value.
    var hasValidAccessibilityData: Bool { get }

    /// Called after a view update event has been sent to clear the changed attributes.
    /// This ensures that only new changes are tracked for the next view update.
    /// Also transitions from first view update to subsequent updates.
    func clearChangedAttributes()

    /// Called when a new view starts to reset the tracking state.
    /// Resets the first view update flag and clears any accumulated changed attributes.
    /// This ensures the new view starts with a clean state and sends all accessibility attributes on its first update.
    func resetForNewView()
}

@available(iOS 13.0, tvOS 13.0, *)
internal final class AccessibilityReader: AccessibilityReading {
    @ReadWriteLock
    private(set) var state: AccessibilityInfo

    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    /// Track if this is the first view update
    private var isFirstViewUpdate = true
    /// Track changed accessibility attributes
    private var changedAttributes: RUMViewEvent.View.Accessibility?

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
            let newState = self.currentState

            // Track changes by comparing with the previous state
            self.trackChanges(from: self.state, to: newState)

            self.state = newState
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

    /// Converts the current accessibility state to RUM View Event accessibility format
    var rumAccessibility: RUMViewEvent.View.Accessibility? {
        // Only proceed if we have a valid state (at least one non-nil value)
        guard hasValidAccessibilityData else {
            return nil
        }

        if isFirstViewUpdate {
            // First view update: return all accessibility attributes
            let accessibility = RUMViewEvent.View.Accessibility(
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
            return accessibility
        } else {
            // Subsequent updates: only return changed attributes
            return createAccessibilityFromChangedAttributes()
        }
    }

    /// Called after a view update event has been sent to clear the changed attributes
    func clearChangedAttributes() {
        changedAttributes = nil

        if isFirstViewUpdate {
            isFirstViewUpdate = false
        }
    }

    /// Called when a new view starts to reset the tracking state
    func resetForNewView() {
        isFirstViewUpdate = true
        changedAttributes = nil
    }

    /// Check if we have valid accessibility data to send
    var hasValidAccessibilityData: Bool {
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

    /// Track changes between two accessibility states
    private func trackChanges(from oldState: AccessibilityInfo, to newState: AccessibilityInfo) {
        // Only track changes if there are actual differences
        if hasChanges(between: oldState, and: newState) {
            self.changedAttributes = RUMViewEvent.View.Accessibility(
                assistiveSwitchEnabled: oldState.assistiveSwitchEnabled != newState.assistiveSwitchEnabled ? newState.assistiveSwitchEnabled : nil,
                assistiveTouchEnabled: oldState.assistiveTouchEnabled != newState.assistiveTouchEnabled ? newState.assistiveTouchEnabled : nil,
                boldTextEnabled: oldState.boldTextEnabled != newState.boldTextEnabled ? newState.boldTextEnabled : nil,
                buttonShapesEnabled: oldState.buttonShapesEnabled != newState.buttonShapesEnabled ? newState.buttonShapesEnabled : nil,
                closedCaptioningEnabled: oldState.closedCaptioningEnabled != newState.closedCaptioningEnabled ? newState.closedCaptioningEnabled : nil,
                grayscaleEnabled: oldState.grayscaleEnabled != newState.grayscaleEnabled ? newState.grayscaleEnabled : nil,
                increaseContrastEnabled: oldState.increaseContrastEnabled != newState.increaseContrastEnabled ? newState.increaseContrastEnabled : nil,
                invertColorsEnabled: oldState.invertColorsEnabled != newState.invertColorsEnabled ? newState.invertColorsEnabled : nil,
                monoAudioEnabled: oldState.monoAudioEnabled != newState.monoAudioEnabled ? newState.monoAudioEnabled : nil,
                onOffSwitchLabelsEnabled: oldState.onOffSwitchLabelsEnabled != newState.onOffSwitchLabelsEnabled ? newState.onOffSwitchLabelsEnabled : nil,
                reduceMotionEnabled: oldState.reduceMotionEnabled != newState.reduceMotionEnabled ? newState.reduceMotionEnabled : nil,
                reduceTransparencyEnabled: oldState.reduceTransparencyEnabled != newState.reduceTransparencyEnabled ? newState.reduceTransparencyEnabled : nil,
                reducedAnimationsEnabled: oldState.reducedAnimationsEnabled != newState.reducedAnimationsEnabled ? newState.reducedAnimationsEnabled : nil,
                rtlEnabled: oldState.rtlEnabled != newState.rtlEnabled ? newState.rtlEnabled : nil,
                screenReaderEnabled: oldState.screenReaderEnabled != newState.screenReaderEnabled ? newState.screenReaderEnabled : nil,
                shakeToUndoEnabled: oldState.shakeToUndoEnabled != newState.shakeToUndoEnabled ? newState.shakeToUndoEnabled : nil,
                shouldDifferentiateWithoutColor: oldState.shouldDifferentiateWithoutColor != newState.shouldDifferentiateWithoutColor ? newState.shouldDifferentiateWithoutColor : nil,
                singleAppModeEnabled: oldState.singleAppModeEnabled != newState.singleAppModeEnabled ? newState.singleAppModeEnabled : nil,
                speakScreenEnabled: oldState.speakScreenEnabled != newState.speakScreenEnabled ? newState.speakScreenEnabled : nil,
                speakSelectionEnabled: oldState.speakSelectionEnabled != newState.speakSelectionEnabled ? newState.speakSelectionEnabled : nil,
                textSize: oldState.textSize != newState.textSize ? newState.textSize : nil,
                videoAutoplayEnabled: oldState.videoAutoplayEnabled != newState.videoAutoplayEnabled ? newState.videoAutoplayEnabled : nil
            )
        } else {
            self.changedAttributes = nil
        }
    }

    /// Check if there are any differences between two accessibility states
    private func hasChanges(between oldState: AccessibilityInfo, and newState: AccessibilityInfo) -> Bool {
        return oldState.assistiveSwitchEnabled != newState.assistiveSwitchEnabled ||
               oldState.assistiveTouchEnabled != newState.assistiveTouchEnabled ||
               oldState.boldTextEnabled != newState.boldTextEnabled ||
               oldState.buttonShapesEnabled != newState.buttonShapesEnabled ||
               oldState.closedCaptioningEnabled != newState.closedCaptioningEnabled ||
               oldState.grayscaleEnabled != newState.grayscaleEnabled ||
               oldState.increaseContrastEnabled != newState.increaseContrastEnabled ||
               oldState.invertColorsEnabled != newState.invertColorsEnabled ||
               oldState.monoAudioEnabled != newState.monoAudioEnabled ||
               oldState.onOffSwitchLabelsEnabled != newState.onOffSwitchLabelsEnabled ||
               oldState.reduceMotionEnabled != newState.reduceMotionEnabled ||
               oldState.reduceTransparencyEnabled != newState.reduceTransparencyEnabled ||
               oldState.reducedAnimationsEnabled != newState.reducedAnimationsEnabled ||
               oldState.screenReaderEnabled != newState.screenReaderEnabled ||
               oldState.shakeToUndoEnabled != newState.shakeToUndoEnabled ||
               oldState.shouldDifferentiateWithoutColor != newState.shouldDifferentiateWithoutColor ||
               oldState.singleAppModeEnabled != newState.singleAppModeEnabled ||
               oldState.speakScreenEnabled != newState.speakScreenEnabled ||
               oldState.speakSelectionEnabled != newState.speakSelectionEnabled ||
               oldState.textSize != newState.textSize ||
               oldState.videoAutoplayEnabled != newState.videoAutoplayEnabled ||
               oldState.rtlEnabled != newState.rtlEnabled
    }

    /// Create accessibility object from changed attributes only
    private func createAccessibilityFromChangedAttributes() -> RUMViewEvent.View.Accessibility? {
        return changedAttributes
    }
}
