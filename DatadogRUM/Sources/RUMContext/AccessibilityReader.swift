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

    /// Track the initial accessibility state for comparison
    private var initialState: AccessibilityInfo?
    /// Track if this is the first view update
    private var isFirstViewUpdate = true
    /// Track changed accessibility attributes
    private var changedAttributes: [String: Any] = [:]

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

            // If this is the first update, store the initial state
            if self.initialState == nil {
                self.initialState = newState
            } else {
                // Track changes by comparing with the previous state
                self.trackChanges(from: self.state, to: newState)
            }

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
        changedAttributes.removeAll()

        if isFirstViewUpdate {
            isFirstViewUpdate = false
        }
    }

    /// Called when a new view starts to reset the tracking state
    func resetForNewView() {
        isFirstViewUpdate = true
        changedAttributes.removeAll()
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
        if oldState.assistiveSwitchEnabled != newState.assistiveSwitchEnabled {
            changedAttributes["assistiveSwitchEnabled"] = newState.assistiveSwitchEnabled
        }
        if oldState.assistiveTouchEnabled != newState.assistiveTouchEnabled {
            changedAttributes["assistiveTouchEnabled"] = newState.assistiveTouchEnabled
        }
        if oldState.boldTextEnabled != newState.boldTextEnabled {
            changedAttributes["boldTextEnabled"] = newState.boldTextEnabled
        }
        if oldState.buttonShapesEnabled != newState.buttonShapesEnabled {
            changedAttributes["buttonShapesEnabled"] = newState.buttonShapesEnabled
        }
        if oldState.closedCaptioningEnabled != newState.closedCaptioningEnabled {
            changedAttributes["closedCaptioningEnabled"] = newState.closedCaptioningEnabled
        }
        if oldState.grayscaleEnabled != newState.grayscaleEnabled {
            changedAttributes["grayscaleEnabled"] = newState.grayscaleEnabled
        }
        if oldState.increaseContrastEnabled != newState.increaseContrastEnabled {
            changedAttributes["increaseContrastEnabled"] = newState.increaseContrastEnabled
        }
        if oldState.invertColorsEnabled != newState.invertColorsEnabled {
            changedAttributes["invertColorsEnabled"] = newState.invertColorsEnabled
        }
        if oldState.monoAudioEnabled != newState.monoAudioEnabled {
            changedAttributes["monoAudioEnabled"] = newState.monoAudioEnabled
        }
        if oldState.onOffSwitchLabelsEnabled != newState.onOffSwitchLabelsEnabled {
            changedAttributes["onOffSwitchLabelsEnabled"] = newState.onOffSwitchLabelsEnabled
        }
        if oldState.reduceMotionEnabled != newState.reduceMotionEnabled {
            changedAttributes["reduceMotionEnabled"] = newState.reduceMotionEnabled
        }
        if oldState.reduceTransparencyEnabled != newState.reduceTransparencyEnabled {
            changedAttributes["reduceTransparencyEnabled"] = newState.reduceTransparencyEnabled
        }
        if oldState.reducedAnimationsEnabled != newState.reducedAnimationsEnabled {
            changedAttributes["reducedAnimationsEnabled"] = newState.reducedAnimationsEnabled
        }
        if oldState.screenReaderEnabled != newState.screenReaderEnabled {
            changedAttributes["screenReaderEnabled"] = newState.screenReaderEnabled
        }
        if oldState.shakeToUndoEnabled != newState.shakeToUndoEnabled {
            changedAttributes["shakeToUndoEnabled"] = newState.shakeToUndoEnabled
        }
        if oldState.shouldDifferentiateWithoutColor != newState.shouldDifferentiateWithoutColor {
            changedAttributes["shouldDifferentiateWithoutColor"] = newState.shouldDifferentiateWithoutColor
        }
        if oldState.singleAppModeEnabled != newState.singleAppModeEnabled {
            changedAttributes["singleAppModeEnabled"] = newState.singleAppModeEnabled
        }
        if oldState.speakScreenEnabled != newState.speakScreenEnabled {
            changedAttributes["speakScreenEnabled"] = newState.speakScreenEnabled
        }
        if oldState.speakSelectionEnabled != newState.speakSelectionEnabled {
            changedAttributes["speakSelectionEnabled"] = newState.speakSelectionEnabled
        }
        if oldState.textSize != newState.textSize {
            changedAttributes["textSize"] = newState.textSize
        }
        if oldState.videoAutoplayEnabled != newState.videoAutoplayEnabled {
            changedAttributes["videoAutoplayEnabled"] = newState.videoAutoplayEnabled
        }
        if oldState.rtlEnabled != newState.rtlEnabled {
            changedAttributes["rtlEnabled"] = newState.rtlEnabled
        }
    }

    /// Create accessibility object from changed attributes only
    private func createAccessibilityFromChangedAttributes() -> RUMViewEvent.View.Accessibility? {
        guard !changedAttributes.isEmpty else {
            return nil
        }

        return RUMViewEvent.View.Accessibility(
            assistiveSwitchEnabled: changedAttributes["assistiveSwitchEnabled"] as? Bool,
            assistiveTouchEnabled: changedAttributes["assistiveTouchEnabled"] as? Bool,
            boldTextEnabled: changedAttributes["boldTextEnabled"] as? Bool,
            buttonShapesEnabled: changedAttributes["buttonShapesEnabled"] as? Bool,
            closedCaptioningEnabled: changedAttributes["closedCaptioningEnabled"] as? Bool,
            grayscaleEnabled: changedAttributes["grayscaleEnabled"] as? Bool,
            increaseContrastEnabled: changedAttributes["increaseContrastEnabled"] as? Bool,
            invertColorsEnabled: changedAttributes["invertColorsEnabled"] as? Bool,
            monoAudioEnabled: changedAttributes["monoAudioEnabled"] as? Bool,
            onOffSwitchLabelsEnabled: changedAttributes["onOffSwitchLabelsEnabled"] as? Bool,
            reduceMotionEnabled: changedAttributes["reduceMotionEnabled"] as? Bool,
            reduceTransparencyEnabled: changedAttributes["reduceTransparencyEnabled"] as? Bool,
            reducedAnimationsEnabled: changedAttributes["reducedAnimationsEnabled"] as? Bool,
            rtlEnabled: changedAttributes["rtlEnabled"] as? Bool,
            screenReaderEnabled: changedAttributes["screenReaderEnabled"] as? Bool,
            shakeToUndoEnabled: changedAttributes["shakeToUndoEnabled"] as? Bool,
            shouldDifferentiateWithoutColor: changedAttributes["shouldDifferentiateWithoutColor"] as? Bool,
            singleAppModeEnabled: changedAttributes["singleAppModeEnabled"] as? Bool,
            speakScreenEnabled: changedAttributes["speakScreenEnabled"] as? Bool,
            speakSelectionEnabled: changedAttributes["speakSelectionEnabled"] as? Bool,
            textSize: changedAttributes["textSize"] as? String,
            videoAutoplayEnabled: changedAttributes["videoAutoplayEnabled"] as? Bool
        )
    }
}
