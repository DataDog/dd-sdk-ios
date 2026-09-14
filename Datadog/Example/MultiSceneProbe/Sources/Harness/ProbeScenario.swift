/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

enum ProbeTrackingMode: String, Codable, CaseIterable {
    case automatic
    case manual
    case navigationPath = "navigation-path"
    case navigationOccurrence = "navigation-occurrence"
}

enum ProbeLayout: String, Codable, CaseIterable {
    case stack
    case splitSelection = "split-selection"
    case uikitSplit = "uikit-split"
    case uikitSplitSubclass = "uikit-split-subclass"
    case uikitSplitNavigation = "uikit-split-navigation"
}

enum ProbeRunMode: String, Codable, CaseIterable {
    case clean
    case restoration
}

enum ProbeCapability: String, Codable, CaseIterable, Hashable {
    case multipleScenes = "multiple-scenes"
    case simultaneousVisibleWindows = "simultaneous-visible-windows"
    case regularWidth = "regular-width"
    case nativeSwiftUIGesture = "native-swiftui-gesture"
    case nativeUIKitGesture = "native-uikit-gesture"
    case resizableWindow = "resizable-window"
    case restoration
}

enum ProbeScenarioResolutionSource: String, Codable {
    case commandLine = "command-line"
    case legacyEnvironment = "legacy-environment"
    case defaultScenario = "default"
}

enum ProbeSwiftUIStress: String, Codable, CaseIterable {
    case none
    case tabPreload = "tab-preload"
    case siblingContainerAuthority = "sibling-container-authority"
}

struct ProbeRuntimeOptions: Codable, Equatable {
    var automaticallyNavigates = false
    var automaticallyOpensSecondWindow = false
    var automaticallyClosesSceneB = false
    var automaticallyAbortsDetail = false
    var automaticallyReplacesDetail = false
    var automaticallyReplacesDetailInstance = false
    var forcesNavigationRouteIdentity = false
    var syntheticReaderDisconnectTarget: String?
    var automaticallyPopsUIKitSplitNavigation = true
    var uiKitSplitInteractivePopOutcome: ProbeTransitionOutcome?
    var startsSplitWithoutSelection = false
    var automaticallyAdvancesSplitSelection = true
    var automaticallyReturnsSplitToDetail = false
    var exercisesUIEventContextHandoff = false
    var swiftUIStress = ProbeSwiftUIStress.none
    var semanticNavigationSceneIDs: [String]?
    var manualSwiftUIViewScreensByScene: [String: [String]] = [:]
}

struct ProbeScenario: Codable, Equatable {
    let identifier: String
    let trackingMode: ProbeTrackingMode
    let layout: ProbeLayout
    let initialWindows: [String]
    let defaultRunMode: ProbeRunMode
    let requiredCapabilities: [ProbeCapability]
    let steps: [ProbeStep]
    let completionConditions: [ProbeExpectation]
    let expectedSemanticTimeline: [ProbeExpectation]
    let runtimeOptions: ProbeRuntimeOptions

    init(
        identifier: String,
        trackingMode: ProbeTrackingMode,
        layout: ProbeLayout,
        initialWindows: [String] = ["scene-A"],
        defaultRunMode: ProbeRunMode = .clean,
        requiredCapabilities: [ProbeCapability] = [],
        steps: [ProbeStep],
        completionConditions: [ProbeExpectation],
        expectedSemanticTimeline: [ProbeExpectation],
        runtimeOptions: ProbeRuntimeOptions = ProbeRuntimeOptions()
    ) {
        self.identifier = identifier
        self.trackingMode = trackingMode
        self.layout = layout
        self.initialWindows = initialWindows
        self.defaultRunMode = defaultRunMode
        self.requiredCapabilities = requiredCapabilities
        self.steps = steps
        self.completionConditions = completionConditions
        self.expectedSemanticTimeline = expectedSemanticTimeline
        self.runtimeOptions = runtimeOptions
    }
}

struct ProbeScenarioManifest: Codable, Equatable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let runID: String
    let runMode: ProbeRunMode
    let resolutionSource: ProbeScenarioResolutionSource
    let scenario: ProbeScenario?
    let validationErrors: [String]

    init(
        runID: String,
        runMode: ProbeRunMode,
        resolutionSource: ProbeScenarioResolutionSource,
        scenario: ProbeScenario?,
        validationErrors: [String]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.runID = runID
        self.runMode = runMode
        self.resolutionSource = resolutionSource
        self.scenario = scenario
        self.validationErrors = validationErrors
    }

    var isValid: Bool {
        scenario != nil && validationErrors.isEmpty
    }
}

struct ProbeScenarioResolution {
    let manifest: ProbeScenarioManifest

    var scenario: ProbeScenario? {
        manifest.scenario
    }

    var isValid: Bool {
        manifest.isValid
    }
}
