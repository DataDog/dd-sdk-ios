/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

enum ProbeStepKind: String, Codable, CaseIterable {
    case waitForSceneReady = "wait-for-scene-ready"
    case openWindow = "open-window"
    case activateWindow = "activate-window"
    case closeWindow = "close-window"
    case setSwiftUIPath = "set-swiftui-path"
    case setSwiftUIPresentation = "set-swiftui-presentation"
    case startKeyedManualView = "start-keyed-manual-view"
    case stopKeyedManualView = "stop-keyed-manual-view"
    case replaceSwiftUIDestination = "replace-swiftui-destination"
    case pushAndRevertSwiftUIPath = "push-and-revert-swiftui-path"
    case setSplitSelection = "set-split-selection"
    case beginUIKitInteractiveTransition = "begin-uikit-interactive-transition"
    case updateUIKitInteractiveTransition = "update-uikit-interactive-transition"
    case resolveUIKitInteractiveTransition = "resolve-uikit-interactive-transition"
    case armNativeSwiftUIGesture = "arm-native-swiftui-gesture"
    case armNativeUIKitGesture = "arm-native-uikit-gesture"
    case emitMarker = "emit-marker"
    case emitSceneContextMarker = "emit-scene-context-marker"
    case disconnectRetainedReader = "disconnect-retained-reader"
    case waitForSignal = "wait-for-signal"
}

enum ProbeTransitionOutcome: String, Codable, CaseIterable {
    case cancel
    case finish
}

struct ProbeStep: Codable, Equatable {
    let kind: ProbeStepKind
    let scene: String?
    let value: String?
    let outcome: ProbeTransitionOutcome?
    let percentage: Double?
    let signal: String?

    init(
        _ kind: ProbeStepKind,
        scene: String? = nil,
        value: String? = nil,
        outcome: ProbeTransitionOutcome? = nil,
        percentage: Double? = nil,
        signal: String? = nil
    ) {
        self.kind = kind
        self.scene = scene
        self.value = value
        self.outcome = outcome
        self.percentage = percentage
        self.signal = signal
    }
}
