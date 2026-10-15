/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Included only in the isolated activation fixture. The existing input observer
/// supplies actual UIKit state and a synchronous notification history.
@MainActor
private final class ProbeFocusActivationAdmission {
    static let scenarioID = "windows.focus-activation-only"
    static let profile = "physical-focus-activation-only"
    private let input: ProbePhysicalOperationInput
    private let recorder: ProbeEventRecorder
    private var owners: [ProbePhysicalOperationEventLedger.Owner]?
    private var before: ProbePhysicalInputSnapshot?
    private var observers: [String]?
    private var nextMarker = 0
    private var failure: String?
    private let indices = [4, 7, 10, 13]
    private let scenes = ["scene-B", "scene-A", "scene-B", "scene-A"]
    private let names = ["after-initial-activate-B", "after-activate-A", "after-reactivate-B", "after-reactivate-A"]

    init(input: ProbePhysicalOperationInput, recorder: ProbeEventRecorder) {
        self.input = input
        self.recorder = recorder
    }

    private func validate(_ value: ProbePhysicalInputSnapshot, target: String) -> String? {
        if let reason = value.failure ?? value.continuity?.failure { return reason }
        guard value.applicationActive, let continuity = value.continuity,
              continuity.owners.map(\.logicalSceneID) == ["scene-A", "scene-B"],
              value.scenes.map(\.logicalSceneID) == ["scene-A", "scene-B"],
              value.input.map(\.logicalSceneID) == ["scene-A", "scene-B"],
              Set(continuity.owners.map(\.nativeSceneID)).count == 2,
              Set(continuity.owners.map(\.windowIdentity)).count == 2,
              Set(continuity.owners.map(\.rootIdentity)).count == 2,
              Set(value.input.map(\.observerIdentity)).count == 2,
              value.connectedSceneIDs.sorted() == continuity.owners.map(\.nativeSceneID).sorted(),
              value.inventory.map(\.nativeSceneID).sorted() == value.connectedSceneIDs.sorted()
        else { return "focus scene or continuity inventory is incomplete" }
        if let owners, owners != continuity.owners { return "focus scene/window/controller owner changed" }
        if let observers, observers != value.input.map(\.observerIdentity) { return "focus input observer changed" }
        for owner in continuity.owners {
            guard let scene = value.scenes.first(where: { $0.logicalSceneID == owner.logicalSceneID }),
                  let input = value.input.first(where: { $0.logicalSceneID == owner.logicalSceneID }),
                  let inventory = value.inventory.first(where: { $0.nativeSceneID == owner.nativeSceneID }),
                  scene.nativeSceneID == owner.nativeSceneID, scene.generation == owner.generation,
                  scene.windowIdentity == owner.windowIdentity, scene.rootIdentity == owner.rootIdentity,
                  input.nativeSceneID == owner.nativeSceneID, input.generation == owner.generation,
                  input.windowIdentity == owner.windowIdentity, input.rootIdentity == owner.rootIdentity,
                  scene.connected, input.attached, input.enabled, input.reliable, input.touches == 0,
                  !input.observerIdentity.isEmpty,
                  scene.activationState == (owner.logicalSceneID == target ? "foreground-active" : "background"),
                  inventory.activationState == scene.activationState
            else { return "target is not active or peer is not background with its original owner" }
            let windows = inventory.windows.filter { $0.fixtureOwner == owner.logicalSceneID }
            guard windows.count == 1, let window = windows.first,
                  window.identity == owner.windowIdentity, window.rootIdentity == owner.rootIdentity,
                  window.sceneMatches,
                  inventory.windows.filter({ $0.identity == owner.windowIdentity }).count == 1,
                  inventory.windows.filter({ $0.key }).map(\.identity) == (inventory.keyWindowIdentity.map({ [$0] }) ?? [])
            else { return "owned window/controller or complete key-window inventory changed" }
            if owner.logicalSceneID == target &&
                (inventory.keyWindowIdentity != owner.windowIdentity || window.hidden || !window.mounted || !window.alpha.isFinite || window.alpha <= 0) {
                return "active fixture window is not the visible key owner"
            }
        }
        return nil
    }

    func check(index: Int, step: ProbeStep, after: Bool) -> String? {
        if let failure { return failure }
        guard indices.contains(index) else { return nil }
        guard nextMarker < indices.count, index == indices[nextMarker], step.kind == .emitMarker,
              step.scene == scenes[nextMarker], step.value == names[nextMarker],
              (before != nil) == after else { failure = "repeated, skipped or wrong focus marker"; return failure }
        let value = input.snapshot()
        failure = validate(value, target: scenes[nextMarker])
        if failure == nil, after, let previous = before?.continuity, let current = value.continuity {
            let old = previous.events, events = current.events
            if events != old {
                failure = "focus ownership or lifecycle changed during marker dispatch"
            }
        }
        do {
            let data = try JSONEncoder().encode(value)
            guard let detail = String(data: data, encoding: .utf8) else { return "focus witness encoding failed" }
            recorder.record(ProbeSignal(kind: .assertion, stepIndex: index, stepKind: .emitMarker,
                name: "focus-activation-\(after ? "after" : "before")-\(index)",
                result: failure == nil ? .pass : .inconclusive, reason: detail))
        } catch { failure = "focus witness encoding failed" }
        if failure == nil {
            if after { before = nil; nextMarker += 1 }
            else { before = value; owners = value.continuity?.owners; observers = value.input.map(\.observerIdentity) }
        }
        return failure
    }
}
