// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.

/// Synchronous pre-dispatch guard for the isolated H10 fixture. This component
/// does not dispatch SDK work, record signals, qualify display or authorize cleanup.
@MainActor
internal final class ProbeSceneBackgroundGuard {
    private enum Stage { case unarmed, ready, before, invoked, finished }
    private enum Phase { case before, background, foreground }
    private static let markers: [(name: String, scene: String, phase: Phase)] = [
        ("A.before-background", "scene-A", .before),
        ("B.before-background", "scene-B", .before),
        ("B.while-A-background", "scene-B", .background),
        ("A.after-foreground", "scene-A", .foreground),
        ("B.after-A-foreground", "scene-B", .foreground)
    ]
    private static let labels = ["scene-A", "scene-B"]
    private static let notificationKeys: Set<String> = [
        "sceneActivate", "sceneDeactivate", "sceneForeground", "sceneBackground", "sceneDisconnect",
        "windowVisible", "windowHidden", "windowKey", "windowResignKey",
        "appResignActive", "appActive", "appBackground", "appForeground"
    ]
    private static let geometryEvents: Set<String> = [
        "registry-registration", "registry-ready", "registry-presentation",
        "reader-presentation", "resize-began", "resize-ended"
    ]
    private let runID: String
    private var stage = Stage.unarmed
    private var nextMarker = 0
    private var owners: [ProbePhysicalOperationEventLedger.Owner]?
    private var observers: [String]?
    private var names: [String: String]?
    private var previous: [ProbePhysicalOperationEventLedger.Event] = []
    private var auxiliary: Set<String> = []
    private var armRevision: Int?
    private(set) var failure: String?

    init(runID: String) { self.runID = runID }
    var complete: Bool { failure == nil && stage == .finished }

    private func reject(_ reason: String) -> String? {
        failure = failure ?? reason
        return failure
    }

    func arm(_ value: ProbeSceneBackgroundWitness) -> String? {
        if let failure { return failure }
        guard stage == .unarmed else { return reject("background cycle arm reused") }
        if let reason = inspect(value, phase: .before) { return reject(reason) }
        guard let continuity = value.snapshot.continuity else { return reject("continuity missing at arm") }
        owners = continuity.owners
        observers = value.snapshot.input.map(\.observerIdentity)
        names = value.notificationNames
        armRevision = continuity.events.count
        stage = .ready
        return nil
    }

    func before(_ value: ProbeSceneBackgroundWitness, marker: String, scene: String, nativeSceneID: String) -> String? {
        if let failure { return failure }
        guard stage == .ready, matches(marker, scene: scene, native: nativeSceneID) else {
            return reject("background marker missing, repeated or has the wrong owner")
        }
        if let reason = inspect(value, phase: Self.markers[nextMarker].phase) { return reject(reason) }
        stage = .before
        return nil
    }

    /// Call only after the actual synchronous scene-context SDK dispatch returns.
    func invoked(marker: String, scene: String, nativeSceneID: String) -> String? {
        if let failure { return failure }
        guard stage == .before, matches(marker, scene: scene, native: nativeSceneID) else {
            return reject("background invocation lacks its preceding native guard")
        }
        stage = .invoked
        return nil
    }

    func after(_ value: ProbeSceneBackgroundWitness, marker: String, scene: String, nativeSceneID: String) -> String? {
        if let failure { return failure }
        guard stage == .invoked, matches(marker, scene: scene, native: nativeSceneID) else {
            return reject("background completion lacks its matching invocation")
        }
        if let reason = inspect(value, phase: Self.markers[nextMarker].phase) { return reject(reason) }
        nextMarker += 1
        stage = nextMarker == Self.markers.count ? .finished : .ready
        return nil
    }

    private func matches(_ marker: String, scene: String, native: String) -> Bool {
        guard nextMarker < Self.markers.count, let owners else { return false }
        let expected = Self.markers[nextMarker]
        return marker == expected.name && scene == expected.scene
            && owners.first(where: { $0.logicalSceneID == scene })?.nativeSceneID == native
    }

    private static func geometry(_ value: ProbeGeometry) -> Bool {
        [value.x, value.y, value.width, value.height].allSatisfy(\.isFinite)
            && value.width > 0 && value.height > 0
    }

    private func inspect(_ witness: ProbeSceneBackgroundWitness, phase: Phase) -> String? {
        let value = witness.snapshot, typed = witness.notificationNames
        guard !runID.isEmpty, witness.runID == runID, witness.schemaVersion == 1,
              witness.scenarioID == "windows.isolated-background-foreground",
              witness.profile == "physical-isolated-background-foreground",
              Set(typed.keys) == Self.notificationKeys, typed.values.allSatisfy({ !$0.isEmpty }),
              Set(typed.values).count == Self.notificationKeys.count,
              names == nil || names == typed else { return "background witness identity or notification names differ" }
        if let reason = value.failure ?? value.continuity?.failure { return reason }
        guard value.applicationActive, let continuity = value.continuity,
              continuity.owners.map(\.logicalSceneID) == Self.labels,
              value.scenes.map(\.logicalSceneID) == Self.labels,
              value.input.map(\.logicalSceneID) == Self.labels,
              witness.interaction.map(\.logicalSceneID) == Self.labels else { return "background native inventory incomplete" }
        let currentOwners = continuity.owners
        for identities in [currentOwners.map(\.nativeSceneID), currentOwners.map(\.sceneIdentity),
                           currentOwners.map(\.windowIdentity), currentOwners.map(\.rootIdentity),
                           value.input.map(\.observerIdentity)] {
            guard identities.allSatisfy({ !$0.isEmpty }), Set(identities).count == 2 else { return "background native identity aliased" }
        }
        guard (owners == nil || owners == currentOwners),
              (observers == nil || observers == value.input.map(\.observerIdentity)),
              value.connectedSceneIDs == currentOwners.map(\.nativeSceneID).sorted(),
              value.inventory.map(\.nativeSceneID).sorted() == value.connectedSceneIDs else {
            return "background native owner or connection inventory changed"
        }
        let windows = value.inventory.flatMap(\.windows)
        guard windows.allSatisfy({ !$0.identity.isEmpty }), Set(windows.map(\.identity)).count == windows.count else {
            return "background window inventory contains duplicate identities"
        }
        let observedAuxiliary = Set(windows.filter { $0.fixtureOwner == nil && $0.sceneMatches }.map(\.identity))
        guard observedAuxiliary.isDisjoint(with: currentOwners.map(\.windowIdentity)) else {
            return "background fixture window classified as auxiliary"
        }
        for index in Self.labels.indices {
            let owner = currentOwners[index], scene = value.scenes[index], input = value.input[index]
            let interaction = witness.interaction[index]
            guard let inventory = value.inventory.first(where: { $0.nativeSceneID == owner.nativeSceneID }),
                  scene.nativeSceneID == owner.nativeSceneID, scene.generation == owner.generation,
                  scene.windowIdentity == owner.windowIdentity, scene.rootIdentity == owner.rootIdentity,
                  input.nativeSceneID == owner.nativeSceneID, input.generation == owner.generation,
                  input.windowIdentity == owner.windowIdentity, input.rootIdentity == owner.rootIdentity,
                  interaction.windowIdentity == owner.windowIdentity, interaction.rootIdentity == owner.rootIdentity,
                  scene.connected, input.attached, input.enabled, input.reliable, input.touches == 0,
                  !input.transitioning, !input.resizing else { return "background owner input is held, changed or unobservable" }
            let isBackground = phase == .background && owner.logicalSceneID == "scene-A"
            let stateMatches = isBackground ? scene.activationState == "background"
                : ["foreground-active", "foreground-inactive"].contains(scene.activationState)
            guard stateMatches, inventory.activationState == scene.activationState,
                  Self.geometry(scene.geometry), Self.geometry(inventory.geometry), Self.geometry(inventory.screenGeometry) else {
                return "background phase or native geometry differs"
            }
            let owned = inventory.windows.filter { $0.fixtureOwner == owner.logicalSceneID }
            guard owned.count == 1, let window = owned.first,
                  window.identity == owner.windowIdentity, window.rootIdentity == owner.rootIdentity, window.sceneMatches,
                  inventory.windows.filter({ $0.key }).map(\.identity) == (inventory.keyWindowIdentity.map({ [$0] }) ?? []) else {
                return "background owned window or key inventory differs"
            }
            if !isBackground {
                guard !scene.hidden, scene.alpha.isFinite, scene.alpha > 0,
                      !window.hidden, window.alpha.isFinite, window.alpha > 0,
                      window.mounted, input.mounted, interaction.windowEnabled, interaction.rootEnabled,
                      Self.geometry(window.geometry) else { return "background foreground owner is not usable" }
                if scene.activationState == "foreground-active" && inventory.keyWindowIdentity != owner.windowIdentity {
                    return "background active owner lost its key window"
                }
            }
        }
        let events = continuity.events
        guard events.enumerated().allSatisfy({ $0.element.revision == UInt64($0.offset + 1) }),
              events.count >= previous.count, Array(events.prefix(previous.count)) == previous else {
            return "background lifecycle history missing or replaced"
        }
        let allAuxiliary = auxiliary.union(observedAuxiliary)
        if let armRevision {
            let windowNames = Set(["windowVisible", "windowHidden", "windowKey", "windowResignKey"].compactMap { typed[$0] })
            let known = Set(typed.values).union(Self.geometryEvents)
            var background: [UInt64] = [], foreground: [UInt64] = []
            for event in events.dropFirst(armRevision) {
                guard known.contains(event.kind) else { return "unknown background lifecycle event" }
                if let owner = event.owner {
                    guard currentOwners.contains(owner), event.objectIdentity == owner.sceneIdentity || event.objectIdentity == owner.windowIdentity else {
                        return "background lifecycle event has a different owner or object"
                    }
                }
                if Self.geometryEvents.contains(event.kind) || event.kind == typed["sceneActivate"] || event.kind == typed["sceneDeactivate"] {
                    guard let owner = event.owner, event.objectIdentity == owner.sceneIdentity else { return "unowned background scene event" }
                }
                if windowNames.contains(event.kind) {
                    if let owner = event.owner {
                        guard event.objectIdentity == owner.windowIdentity else { return "background window event has a different object" }
                    } else {
                        guard let object = event.objectIdentity, allAuxiliary.contains(object) else { return "unbound auxiliary window event" }
                    }
                }
                if event.kind == typed["appBackground"] || event.kind == typed["appForeground"] { return "whole application changed foreground membership" }
                if [typed["sceneBackground"], typed["sceneForeground"], typed["sceneDisconnect"]].contains(event.kind) {
                    guard let owner = event.owner, event.objectIdentity == owner.sceneIdentity,
                          owner.logicalSceneID == "scene-A", event.kind != typed["sceneDisconnect"] else {
                        return "peer changed foreground membership or a scene disconnected"
                    }
                    if event.kind == typed["sceneBackground"] { background.append(event.revision) }
                    else { foreground.append(event.revision) }
                }
                if event.kind == typed["windowHidden"], event.objectIdentity == currentOwners[1].windowIdentity {
                    return "peer fixture window became hidden"
                }
            }
            switch phase {
            case .before:
                guard background.isEmpty && foreground.isEmpty else { return "background cycle began before its instruction" }
            case .background:
                guard !background.isEmpty && foreground.isEmpty else { return "fresh A background boundary missing" }
            case .foreground:
                guard let lastBackground = background.max(), let firstForeground = foreground.min(), lastBackground < firstForeground else {
                    return "fresh ordered A background and foreground boundaries missing"
                }
            }
        }
        previous = events
        auxiliary = allAuxiliary
        return nil
    }
}
