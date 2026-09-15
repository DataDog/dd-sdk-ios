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
    case startTraceOnlyURLSessionRequest = "start-trace-only-url-session-request"
    case joinTraceOnlyURLSessionRequest = "join-trace-only-url-session-request"
    case completeTraceOnlyURLSessionRequest = "complete-trace-only-url-session-request"
    case releaseSwiftUIButtonStructuredTask = "release-swiftui-button-structured-task"
    case startOperation = "start-operation"
    case succeedOperation = "succeed-operation"
    case failOperation = "fail-operation"
    case disconnectRetainedReader = "disconnect-retained-reader"
    case waitForSignal = "wait-for-signal"
}

enum ProbeSwiftUIButtonStructuredTaskContract {
    static let buttonTitle = "Run structured task"
    static let automaticActionName = "SwiftUI_Button"
    static let startedAssertion = "swiftui-button-structured-task-started"
    static let completedAssertion = "swiftui-button-structured-task-completed"
    static let resumedMarker = "swiftui-button-structured-task-resumed"
    static let representativeMarker = "swiftui-button-task-completion-representative"
}

enum ProbeTraceOnlyURLSessionContract {
    static let host = "multi-scene-probe.invalid"
    static let requestName = "trace-only-home-request"
    static let sharedRequestName = "trace-only-shared-request"
    static let reverseSceneARequestName = "trace-only-reverse-scene-a"
    static let reverseSceneBRequestName = "trace-only-reverse-scene-b"

    static func supports(requestName: String) -> Bool {
        requestName == self.requestName
            || requestName == sharedRequestName
            || requestName == reverseSceneARequestName
            || requestName == reverseSceneBRequestName
    }

    static func requestURL(
        runID: String,
        sourceScene: String,
        sourceScreen: String,
        requestName: String
    ) -> URL {
        URL(string: "https://\(host)")!
            .appendingPathComponent("trace-only")
            .appendingPathComponent(runID)
            .appendingPathComponent(sourceScene)
            .appendingPathComponent(sourceScreen)
            .appendingPathComponent(requestName)
    }

    static func sourceContext(
        from url: URL,
        expectedRunID: String
    ) -> ProbeSourceContext? {
        guard url.host == host else {
            return nil
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard
            components.count == 5,
            components[0] == "trace-only",
            components[1] == expectedRunID
        else {
            return nil
        }
        return ProbeSourceContext(
            logicalSceneID: components[2],
            screen: components[3],
            phase: components[4]
        )
    }
}

enum ProbeOperationContract {
    static let name = "multi_scene_probe_navigation"

    static func key(runID: String, instance: String) -> String {
        "\(runID)-\(instance)"
    }
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
