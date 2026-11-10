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

#if os(macOS)
/// The accessibility settings that macOS exposes through `NSWorkspace`.
internal protocol MacOSAccessibilitySettings: AnyObject {
    var accessibilityDisplayShouldIncreaseContrast: Bool { get }
    var accessibilityDisplayShouldDifferentiateWithoutColor: Bool { get }
    var accessibilityDisplayShouldReduceTransparency: Bool { get }
    var accessibilityDisplayShouldReduceMotion: Bool { get }
    var accessibilityDisplayShouldInvertColors: Bool { get }
    var isVoiceOverEnabled: Bool { get }
    var isSwitchControlEnabled: Bool { get }

    /// Calls `onChange` when VoiceOver or Switch Control is turned on or off, until the returned observations are released.
    func observeAssistiveTechnologies(_ onChange: @escaping () -> Void) -> [NSObjectProtocol]
}

extension NSWorkspace: MacOSAccessibilitySettings {
    func observeAssistiveTechnologies(_ onChange: @escaping () -> Void) -> [NSObjectProtocol] {
        // Both properties are key-value observable. Display options are posted as a notification instead.
        [
            observe(\.isVoiceOverEnabled) { _, _ in onChange() },
            observe(\.isSwitchControlEnabled) { _, _ in onChange() },
        ]
    }
}
#endif

#if !os(watchOS)
internal final class AccessibilityReader: AccessibilityReading {
    @ReadWriteLock
    private(set) var state: AccessibilityInfo

    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    #if os(macOS)
    private let settings: MacOSAccessibilitySettings
    private let layoutDirection: @MainActor () -> NSUserInterfaceLayoutDirection?
    private var assistiveTechnologiesObservations: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - notificationCenter: The notification center where `NSWorkspace` notifications are posted.
    ///   - settings: Provides the accessibility settings.
    ///   - layoutDirection: Provides the app's user interface layout direction, `nil` if it is unknown.
    init(
        notificationCenter: NotificationCenter,
        settings: MacOSAccessibilitySettings = NSWorkspace.shared,
        layoutDirection: @escaping @MainActor () -> NSUserInterfaceLayoutDirection? = { NSApp?.userInterfaceLayoutDirection }
    ) {
        self.state = AccessibilityInfo()
        self.notificationCenter = notificationCenter
        self.settings = settings
        self.layoutDirection = layoutDirection
        startObserving()
        updateState()
    }
    #else
    init(notificationCenter: NotificationCenter) {
        self.state = AccessibilityInfo()
        self.notificationCenter = notificationCenter
        startObserving()
        updateState()
    }
    #endif

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
        #elseif os(macOS)
        let displayOptionsObserver = notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        observers.append(displayOptionsObserver)

        assistiveTechnologiesObservations = settings.observeAssistiveTechnologies { [weak self] in
            self?.updateState()
        }
        #endif
    }

    private func stopObserving() {
        observers.forEach { notificationCenter.removeObserver($0) }
        observers.removeAll()
        #if os(macOS)
        assistiveTechnologiesObservations.removeAll()
        #endif
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
        state.buttonShapesEnabled = UIAccessibility.buttonShapesEnabled
        state.reducedAnimationsEnabled = UIAccessibility.prefersCrossFadeTransitions
        #elseif os(macOS)
        // macOS has no public API for the other settings, so they stay unknown.
        state.increaseContrastEnabled = settings.accessibilityDisplayShouldIncreaseContrast
        state.shouldDifferentiateWithoutColor = settings.accessibilityDisplayShouldDifferentiateWithoutColor
        state.reduceTransparencyEnabled = settings.accessibilityDisplayShouldReduceTransparency
        state.reduceMotionEnabled = settings.accessibilityDisplayShouldReduceMotion
        state.invertColorsEnabled = settings.accessibilityDisplayShouldInvertColors
        state.screenReaderEnabled = settings.isVoiceOverEnabled
        state.assistiveSwitchEnabled = settings.isSwitchControlEnabled
        if let layoutDirection = layoutDirection() {
            state.rtlEnabled = layoutDirection == .rightToLeft
        }
        #endif

        return state
    }
}

#endif
