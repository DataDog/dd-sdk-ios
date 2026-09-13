/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

enum ProbeExpectationKind: String, Codable, CaseIterable {
    case sceneReady = "scene-ready"
    case sceneDisconnected = "scene-disconnected"
    case transitionBegan = "transition-began"
    case transitionResolved = "transition-resolved"
    case destinationMaterialized = "destination-materialized"
    case viewStarted = "view-started"
    case viewStopped = "view-stopped"
    case action = "action"
    case resource = "resource"
    case error = "error"
    case trace = "trace"
    case operationStep = "operation-step"
    case noViewStarted = "no-view-started"
    case noEvent = "no-event"
}

enum ProbeRUMViewOrigin: String, Codable, CaseIterable {
    case semantic
    case automatic
}

struct ProbeExpectation: Codable, Equatable {
    let kind: ProbeExpectationKind
    let scene: String?
    let screen: String?
    let occurrence: Int?
    let name: String?
    let sourceScene: String?
    let sourceScreen: String?
    let rumViewOrigin: ProbeRUMViewOrigin?
    let ownerViewStartedAfterSceneOpen: String?
    let interval: String?
    let outcome: ProbeTransitionOutcome?

    init(
        _ kind: ProbeExpectationKind,
        scene: String? = nil,
        screen: String? = nil,
        occurrence: Int? = nil,
        name: String? = nil,
        sourceScene: String? = nil,
        sourceScreen: String? = nil,
        rumViewOrigin: ProbeRUMViewOrigin? = nil,
        ownerViewStartedAfterSceneOpen: String? = nil,
        interval: String? = nil,
        outcome: ProbeTransitionOutcome? = nil
    ) {
        self.kind = kind
        self.scene = scene
        self.screen = screen
        self.occurrence = occurrence
        self.name = name
        self.sourceScene = sourceScene
        self.sourceScreen = sourceScreen
        self.rumViewOrigin = rumViewOrigin
        self.ownerViewStartedAfterSceneOpen = ownerViewStartedAfterSceneOpen
        self.interval = interval
        self.outcome = outcome
    }
}
