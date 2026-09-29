/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation
import UIKit

/// Exact fixture profile for the existing inferred Operation scenario. This
/// prepares the contract only; input-idle and host transport remain separate.
internal struct ProbePhysicalOperationProfile: Codable, Equatable {
    static let scenarioID = "operations.cross-scene.lifecycle"
    static let receiptSuffix = ".operations-physical-admission.json"
    static let criticalInterval = 6...21
    static let inferenceMechanism = "debug-rum-ui-event-network-context"

    let sourceRevision: String
    let buildConfiguration: String
    let scenarioSHA256: String
    let inference: String

    static var steps: [ProbeStep] {
        let calls: [(ProbeStepKind, String, String, String)] = [
            (.startOperation, "scene-A", "cross-success", "operation-cross-success-start-a"),
            (.succeedOperation, "scene-B", "cross-success", "operation-cross-success-end-b"),
            (.startOperation, "scene-A", "cross-failure", "operation-cross-failure-start-a"),
            (.failOperation, "scene-B", "cross-failure", "operation-cross-failure-end-b"),
            (.startOperation, "scene-A", "parallel-alpha", "operation-parallel-alpha-start-a"),
            (.startOperation, "scene-B", "parallel-beta", "operation-parallel-beta-start-b"),
            (.succeedOperation, "scene-B", "parallel-beta", "operation-parallel-beta-end-b"),
            (.succeedOperation, "scene-A", "parallel-alpha", "operation-parallel-alpha-end-a")
        ]
        return [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-A", value: "operation-cross-home-a"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "rum-view:home#1"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-B", value: "operation-cross-home-b")
        ] + calls.flatMap { kind, scene, instance, marker in
            [ProbeStep(kind, scene: scene, value: instance),
             ProbeStep(.emitSceneContextMarker, scene: scene, value: marker)]
        }
    }

    static func make(scenario: ProbeScenario, sourceRevision: String, buildConfiguration: String) -> Self? {
        guard let canonical = ProbeScenarioCatalog.all.first(where: { $0.identifier == scenarioID }),
              scenario == canonical, scenario.identifier == scenarioID, scenario.steps == steps,
              scenario.trackingMode == .manual, scenario.layout == .stack,
              scenario.initialWindows == ["scene-A", "scene-B"],
              scenario.requiredCapabilities == [.multipleScenes, .simultaneousVisibleWindows],
              scenario.defaultRunMode == .clean,
              sourceRevision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              buildConfiguration == "Debug" else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(scenario) else { return nil }
        return Self(sourceRevision: sourceRevision, buildConfiguration: buildConfiguration,
                    scenarioSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                    inference: inferenceMechanism)
    }

    @MainActor
    static func ownerIdentities(_ scenes: [ProbePhysicalSceneObservation]) -> [String: [String]]? {
        guard ProbePhysicalTopologyAdmission.validateLive(scenes) == nil,
              scenes.allSatisfy({ !($0.windowIdentity ?? "").isEmpty && !($0.rootIdentity ?? "").isEmpty }),
              Set(scenes.compactMap(\.windowIdentity)).count == 2,
              Set(scenes.compactMap(\.rootIdentity)).count == 2 else { return nil }
        return Dictionary(uniqueKeysWithValues: scenes.map {
            ($0.logicalSceneID, [$0.nativeSceneID, String($0.generation), $0.windowIdentity ?? "", $0.rootIdentity ?? ""])
        })
    }

    /// Called before and after each exact step, and by the continuous observer.
    /// A failure is sticky, so later matching observations cannot hide drift.
    @MainActor
    struct Progress {
        let owners: [String: [String]]
        private(set) var nextIndex = criticalInterval.lowerBound
        private(set) var expectsAfter = false
        private(set) var failure: String?
        private(set) var complete = false

        init?(scenes: [ProbePhysicalSceneObservation]) {
            guard let owners = ownerIdentities(scenes) else { return nil }
            self.owners = owners
        }

        mutating func observe(_ scenes: [ProbePhysicalSceneObservation]) -> String? {
            if failure == nil && ownerIdentities(scenes) != owners {
                failure = "Operation scene, window or root owner changed"
            }
            return failure
        }

        mutating func check(index: Int, step: ProbeStep, after: Bool, scenes: [ProbePhysicalSceneObservation]) -> String? {
            if let reason = observe(scenes) { return reason }
            guard !complete, index == nextIndex, after == expectsAfter,
                  criticalInterval.contains(index), step == steps[index] else {
                failure = "Operation admission step is duplicate, late or changed"
                return failure
            }
            if after {
                complete = index == criticalInterval.upperBound
                nextIndex += 1
            }
            expectsAfter = !after
            return nil
        }
    }
}

internal struct ProbePhysicalSceneObservation: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let generation: UInt64
    let connected: Bool
    let activationState: String
    let hidden: Bool
    let alpha: Double
    let geometry: ProbeGeometry
    var windowIdentity: String? = nil
    var rootIdentity: String? = nil
}

internal struct ProbePhysicalTopologyObservation: Codable, Equatable {
    let nonce: String
    let captureID: String?
    let evidenceSHA256: String?
    let scenes: [ProbePhysicalSceneObservation]
}

internal struct ProbePhysicalAdmissionChallenge: Codable {
    let runID: String
    let scenarioID: String
    let processID: Int32
    let nonce: String
    let createdAtMilliseconds: Int64
    let observedAtMilliseconds: Int64
    let scenes: [ProbePhysicalSceneObservation]
}

internal struct ProbePhysicalAdmissionReceipt: Codable {
    var runID: String
    var scenarioID: String
    var processID: Int32
    var nonce: String
    var capturedAtMilliseconds: Int64
    var captureID: String
    var evidenceSHA256: String
    var nativeSceneIDs: [String: String]
    var generations: [String: UInt64]
}

/// Not accepted by the same-key file path or validator. The eventual host must
/// additionally bind release/input-idle, installed binaries and display proof.
internal struct ProbePhysicalOperationReceipt: Codable {
    var topology: ProbePhysicalAdmissionReceipt
    var profile: ProbePhysicalOperationProfile
    var owners: [String: [String]]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(topology: ProbePhysicalAdmissionReceipt, profile: ProbePhysicalOperationProfile, owners: [String: [String]]) {
        self.topology = topology
        self.profile = profile
        self.owners = owners
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        func requireKeys(_ actual: [Key], _ expected: Set<String>) throws {
            guard Set(actual.map(\.stringValue)) == expected else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                       debugDescription: "Unexpected Operation admission fields"))
            }
        }
        try requireKeys(values.allKeys, ["topology", "profile", "owners"])
        let topologyKey = Key(stringValue: "topology")
        let profileKey = Key(stringValue: "profile")
        try requireKeys(values.nestedContainer(keyedBy: Key.self, forKey: topologyKey).allKeys,
                        ["runID", "scenarioID", "processID", "nonce", "capturedAtMilliseconds",
                         "captureID", "evidenceSHA256", "nativeSceneIDs", "generations"])
        try requireKeys(values.nestedContainer(keyedBy: Key.self, forKey: profileKey).allKeys,
                        ["sourceRevision", "buildConfiguration", "scenarioSHA256", "inference"])
        topology = try values.decode(ProbePhysicalAdmissionReceipt.self, forKey: topologyKey)
        profile = try values.decode(ProbePhysicalOperationProfile.self, forKey: profileKey)
        owners = try values.decode([String: [String]].self, forKey: Key(stringValue: "owners"))
    }

    @MainActor
    func validate(profile expected: ProbePhysicalOperationProfile, challenge: ProbePhysicalAdmissionChallenge,
                  live: [ProbePhysicalSceneObservation], now: Int64) -> String? {
        guard profile == expected, challenge.scenarioID == ProbePhysicalOperationProfile.scenarioID,
              let original = ProbePhysicalOperationProfile.ownerIdentities(challenge.scenes),
              let current = ProbePhysicalOperationProfile.ownerIdentities(live),
              owners == original, owners == current else {
            return "Operation profile or owned window/root identity changed"
        }
        return ProbePhysicalTopologyAdmission.validate(topology, challenge: challenge, live: live, now: now)
    }
}

/// Fixture-only barrier. External display evidence establishes visibility;
/// live UIKit observations fence lifecycle/identity changes before mutation.
@MainActor
internal final class ProbePhysicalTopologyAdmission {
    static let scenarioID = "swiftui.coexistence.same-key-manual-two-scenes"
    private let runID: String
    private let registry: ProbeSceneRegistry
    private let recorder: ProbeEventRecorder
    private let directory: URL
    private let nonce = UUID().uuidString
    private var createdAt: Int64 = 0
    private var admitted: ProbePhysicalAdmissionReceipt?
    private var failure: String?
    private var monitor: Task<Void, Never>?

    init(runID: String, registry: ProbeSceneRegistry, recorder: ProbeEventRecorder, directory: URL) {
        self.runID = runID
        self.registry = registry
        self.recorder = recorder
        self.directory = directory
    }

    private var receiptURL: URL { directory.appendingPathComponent(runID + ".physical-admission.json") }
    private var challengeURL: URL { directory.appendingPathComponent(runID + ".physical-challenge.json") }
    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    static func validateLive(_ scenes: [ProbePhysicalSceneObservation]) -> String? {
        guard scenes.map(\.logicalSceneID) == ["scene-A", "scene-B"],
              Set(scenes.map(\.nativeSceneID)).count == 2,
              scenes.allSatisfy({ !$0.nativeSceneID.isEmpty }) else { return "two distinct native scenes required" }
        guard scenes.allSatisfy({ $0.connected && !$0.hidden && $0.alpha.isFinite && $0.alpha > 0
            && ["foreground-active", "foreground-inactive"].contains($0.activationState)
            && [$0.geometry.x, $0.geometry.y, $0.geometry.width, $0.geometry.height].allSatisfy(\.isFinite)
            && $0.geometry.width > 0 && $0.geometry.height > 0 }) else { return "live visible foreground windows required" }
        return nil
    }

    static func validate(
        _ receipt: ProbePhysicalAdmissionReceipt,
        challenge: ProbePhysicalAdmissionChallenge,
        live: [ProbePhysicalSceneObservation],
        now: Int64
    ) -> String? {
        guard receipt.runID == challenge.runID, receipt.scenarioID == challenge.scenarioID,
              receipt.processID == challenge.processID, receipt.nonce == challenge.nonce else {
            return "stale run, process or nonce"
        }
        guard receipt.capturedAtMilliseconds >= challenge.createdAtMilliseconds,
              receipt.capturedAtMilliseconds <= now + 2_000,
              now - receipt.capturedAtMilliseconds <= 60_000 else { return "stale or future display evidence" }
        guard UUID(uuidString: receipt.captureID) != nil,
              receipt.evidenceSHA256.count == 64,
              receipt.evidenceSHA256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            return "independent display capture identity missing"
        }
        if let reason = validateLive(live) { return reason }
        let identities = Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.nativeSceneID) })
        let generations = Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.generation) })
        guard receipt.nativeSceneIDs == identities, receipt.generations == generations,
              Dictionary(uniqueKeysWithValues: challenge.scenes.map { ($0.logicalSceneID, $0.nativeSceneID) }) == identities,
              Dictionary(uniqueKeysWithValues: challenge.scenes.map { ($0.logicalSceneID, $0.generation) }) == generations else {
            return "scene identity or generation changed"
        }
        return nil
    }

    private func observe() -> [ProbePhysicalSceneObservation] {
        ["scene-A", "scene-B"].compactMap { label in
            guard let handle = registry.handle(logicalSceneID: label),
                  let window = registry.window(for: handle), let scene = window.windowScene,
                  let geometry = ProbeScenePresentation.capture(window: window).geometry else { return nil }
            return .init(logicalSceneID: label, nativeSceneID: scene.session.persistentIdentifier,
                         generation: handle.disconnectGeneration,
                         connected: scene.session.persistentIdentifier == handle.nativeSceneID
                            && UIApplication.shared.connectedScenes.contains(scene),
                         activationState: ProbeSceneActivationState(scene.activationState).rawValue,
                         hidden: window.isHidden, alpha: Double(window.alpha), geometry: geometry)
        }
    }

    private func record(_ name: String, scenes: [ProbePhysicalSceneObservation], result: ProbeSemanticResultState, reason: String? = nil) {
        recorder.record(ProbeSignal(kind: .assertion, name: name,
            physicalTopology: .init(nonce: nonce, captureID: admitted?.captureID,
                                   evidenceSHA256: admitted?.evidenceSHA256, scenes: scenes),
            result: result, reason: reason))
    }

    private func checkAdmitted() -> String? {
        if let failure { return failure }
        guard let admitted else { return "physical admission missing" }
        let live = observe()
        if let reason = Self.validateLive(live) { return reason }
        guard Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.nativeSceneID) }) == admitted.nativeSceneIDs,
              Dictionary(uniqueKeysWithValues: live.map { ($0.logicalSceneID, $0.generation) }) == admitted.generations else {
            return "admitted scene identity or generation changed"
        }
        if FileManager.default.fileExists(atPath: receiptURL.path) { return "physical admission receipt reused" }
        return nil
    }

    func check(index: Int, step: ProbeStep, after: Bool) async -> String? {
        guard (6...16).contains(index) else { return nil }
        if admitted == nil && failure == nil {
            guard index == 6 && !after else { return "physical admission arrived after first mutation" }
            createdAt = now
            let original = observe()
            do {
                for _ in 0..<1_200 {
                    let live = observe()
                    let challenge = ProbePhysicalAdmissionChallenge(
                        runID: runID, scenarioID: Self.scenarioID, processID: ProcessInfo.processInfo.processIdentifier,
                        nonce: nonce, createdAtMilliseconds: createdAt, observedAtMilliseconds: now, scenes: live)
                    try JSONEncoder().encode(challenge).write(to: challengeURL, options: .atomic)
                    if FileManager.default.fileExists(atPath: receiptURL.path) {
                        let bytes = try Data(contentsOf: receiptURL)
                        guard bytes.count <= 16_384 else { return "oversized admission receipt" }
                        let receipt = try JSONDecoder().decode(ProbePhysicalAdmissionReceipt.self, from: bytes)
                        let initial = ProbePhysicalAdmissionChallenge(
                            runID: runID, scenarioID: Self.scenarioID, processID: challenge.processID,
                            nonce: nonce, createdAtMilliseconds: createdAt, observedAtMilliseconds: now, scenes: original)
                        if let reason = Self.validate(receipt, challenge: initial, live: live, now: now) {
                            failure = reason
                            break
                        }
                        admitted = receipt
                        try FileManager.default.removeItem(at: receiptURL)
                        record("physical-topology-admitted", scenes: live, result: .pass)
                        monitor = Task { @MainActor [weak self] in
                            while !Task.isCancelled {
                                guard let self else { return }
                                if let reason = self.checkAdmitted() {
                                    self.failure = reason
                                    self.record("physical-topology-lost", scenes: self.observe(), result: .inconclusive, reason: reason)
                                    return
                                }
                                try? await Task.sleep(nanoseconds: 50_000_000)
                            }
                        }
                        break
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            } catch {
                failure = "physical admission file or wait failed"
            }
            if admitted == nil && failure == nil { failure = "timed out before physical topology admission" }
        }
        if let reason = checkAdmitted() { failure = reason }
        record("physical-topology-\(after ? "after" : "before")-\(index)", scenes: observe(),
               result: failure == nil ? .pass : .inconclusive, reason: failure)
        if failure != nil || (index == 16 && after) {
            monitor?.cancel()
            monitor = nil
        }
        return failure
    }
}


/// Contact bookkeeping stays invalid after a lost callback or observer reset.
internal struct ProbePhysicalContactLedger {
    private(set) var active: Set<ObjectIdentifier> = []
    private(set) var revision: UInt64 = 0
    private(set) var reliable = true

    mutating func began(_ contacts: Set<ObjectIdentifier>) {
        advance()
        if !active.isDisjoint(with: contacts) { reliable = false }
        active.formUnion(contacts)
    }

    mutating func moved(_ contacts: Set<ObjectIdentifier>) {
        advance()
        if !contacts.isSubset(of: active) { reliable = false }
    }

    mutating func ended(_ contacts: Set<ObjectIdentifier>) {
        advance()
        if !contacts.isSubset(of: active) { reliable = false }
        active.subtract(contacts)
    }

    mutating func reset() {
        if !active.isEmpty { invalidate() }
    }

    mutating func invalidate() { reliable = false; advance() }

    private mutating func advance() {
        if revision == .max { reliable = false }
        else { revision += 1 }
    }
}

/// Observes contacts delivered to a fixture window; never recognizes a gesture.
/// OS chrome input still requires a separate human release acknowledgement.
@MainActor
internal final class ProbePhysicalTouches: UIGestureRecognizer {
    private(set) var ledger = ProbePhysicalContactLedger()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override var isEnabled: Bool {
        didSet { if !isEnabled { ledger.invalidate() } }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        ledger.began(Set(touches.map(ObjectIdentifier.init)))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        ledger.moved(Set(touches.map(ObjectIdentifier.init)))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        ledger.ended(Set(touches.map(ObjectIdentifier.init)))
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        ledger.ended(Set(touches.map(ObjectIdentifier.init)))
    }
    override func reset() { ledger.reset(); super.reset() }
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}

internal struct ProbePhysicalInputWindow: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let generation: UInt64
    let windowIdentity: String
    let rootIdentity: String
    let observerIdentity: String
    let attached: Bool
    let enabled: Bool
    let reliable: Bool
    let touches: Int
    let revision: UInt64
    let mounted: Bool
    let transitioning: Bool
    let resizing: Bool
}

internal struct ProbePhysicalWindowInventory: Codable, Equatable {
    let identity: String
    let rootIdentity: String?
    let fixtureOwner: String?
    let sceneMatches: Bool
    let key: Bool
    let hidden: Bool
    let alpha: Double
    let mounted: Bool
    let geometry: ProbeGeometry
}

internal struct ProbePhysicalSceneInventory: Codable, Equatable {
    let nativeSceneID: String
    let activationState: String
    let keyWindowIdentity: String?
    let geometry: ProbeGeometry
    let screenGeometry: ProbeGeometry
    let windows: [ProbePhysicalWindowInventory]
}

/// Opt-in event history for the fixed, non-navigating SwiftUI Operation fixture.
/// Notifications are recorded synchronously on their posting thread. Only this
/// lock-protected value ledger crosses threads; it never reads UIKit state.
internal final class ProbePhysicalOperationEventLedger: @unchecked Sendable {
    struct Owner: Codable, Equatable {
        let logicalSceneID: String
        let nativeSceneID: String
        let generation: UInt64
        let sceneIdentity: String
        let windowIdentity: String
        let rootIdentity: String
    }
    struct Event: Codable, Equatable {
        let revision: UInt64
        let kind: String
        let objectIdentity: String?
        let owner: Owner?
    }
    struct Snapshot: Codable, Equatable {
        let owners: [Owner]
        let events: [Event]
        let failure: String?
    }
    private let lock = NSLock()
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private var owners: [String: Owner] = [:]
    private var events: [Event] = []
    private var failure: String?

    init(center: NotificationCenter = .default) {
        self.center = center
        let names = [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
            UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
            UIScene.didDisconnectNotification, UIWindow.didBecomeVisibleNotification,
            UIWindow.didBecomeHiddenNotification, UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification,
            UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification,
            UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification]
        tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                self?.notification(name: notification.name.rawValue,
                    object: notification.object.map { String(describing: ObjectIdentifier($0 as AnyObject)) })
            }
        }
    }
    deinit { tokens.forEach(center.removeObserver) }

    func install(_ owner: Owner) {
        lock.lock(); defer { lock.unlock() }
        if let existing = owners[owner.logicalSceneID] {
            if existing != owner { failure = "registered Operation observer owner replaced" }
        } else { owners[owner.logicalSceneID] = owner }
    }
    func record(_ kind: String, scene: String) {
        lock.lock(); defer { lock.unlock() }
        append(kind, object: owners[scene]?.sceneIdentity, owner: owners[scene])
    }
    private func notification(name: String, object: String?) {
        lock.lock(); defer { lock.unlock() }
        // Preserve unknown/auxiliary objects too. A new event during the frozen
        // interval invalidates continuity without a private-class/count rule.
        let owner = owners.values.first { $0.sceneIdentity == object || $0.windowIdentity == object }
        append(name, object: object, owner: owner)
    }
    private func append(_ kind: String, object: String?, owner: Owner?) {
        guard events.count < 2_048 else { failure = "Operation event history overflow"; return }
        events.append(.init(revision: UInt64(events.count + 1), kind: kind, objectIdentity: object, owner: owner))
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(owners: owners.values.sorted { $0.logicalSceneID < $1.logicalSceneID }, events: events, failure: failure)
    }
}

internal struct ProbePhysicalInputSnapshot: Codable, Equatable {
    let scenes: [ProbePhysicalSceneObservation]
    let input: [ProbePhysicalInputWindow]
    let connectedSceneIDs: [String]
    let applicationActive: Bool
    let inventory: [ProbePhysicalSceneInventory]
    let failure: String?
    var continuity: ProbePhysicalOperationEventLedger.Snapshot? = nil

    @MainActor
    func idleFailure() -> String? {
        if let failure { return failure }
        if let continuity {
            if let reason = continuity.failure { return reason }
            guard continuity.owners.map(\.logicalSceneID) == ["scene-A", "scene-B"],
                  continuity.owners.allSatisfy({ owner in
                      input.contains { $0.logicalSceneID == owner.logicalSceneID && $0.nativeSceneID == owner.nativeSceneID
                          && $0.generation == owner.generation && $0.windowIdentity == owner.windowIdentity
                          && $0.rootIdentity == owner.rootIdentity }
                  }) else { return "Operation continuity observers missing or replaced" }
        }
        guard applicationActive, let owners = ProbePhysicalOperationProfile.ownerIdentities(scenes),
              input.map(\.logicalSceneID) == ["scene-A", "scene-B"],
              Set(input.map(\.observerIdentity)).count == 2 else { return "owned input inventory missing or aliased" }
        for row in input {
            guard owners[row.logicalSceneID] == [row.nativeSceneID, String(row.generation), row.windowIdentity, row.rootIdentity],
                  !row.observerIdentity.isEmpty, row.attached, row.enabled, row.reliable, row.mounted,
                  row.touches == 0, !row.transitioning, !row.resizing else { return "input is active, incomplete or detached" }
            let sceneRows = inventory.filter { $0.nativeSceneID == row.nativeSceneID }
            guard connectedSceneIDs.filter({ $0 == row.nativeSceneID }).count == 1, sceneRows.count == 1,
                  let scene = sceneRows.first else { return "owned native scene inventory missing" }
            let windows = scene.windows.filter { $0.fixtureOwner == row.logicalSceneID }
            guard windows.count == 1, let window = windows.first, window.identity == row.windowIdentity,
                  window.rootIdentity == row.rootIdentity, window.sceneMatches, window.mounted,
                  !window.hidden, window.alpha.isFinite, window.alpha > 0,
                  scene.windows.filter({ $0.identity == row.windowIdentity }).count == 1,
                  scene.windows.filter({ $0.key }).map(\.identity) == (scene.keyWindowIdentity.map({ [$0] }) ?? []) else {
                return "owned window or key-window inventory differs"
            }
        }
        return nil
    }
}

/// Installed once per original fixture owner, before scene-ready publication.
/// Repeated SwiftUI layout callbacks never replace the observer or its ledger.
@MainActor
internal final class ProbePhysicalOperationInput {
    @MainActor private final class Entry {
        let handle: ProbeSceneHandle
        weak var window: UIWindow?
        weak var root: UIViewController?
        let touches: ProbePhysicalTouches
        init(handle: ProbeSceneHandle, window: UIWindow, root: UIViewController) {
            self.handle = handle; self.window = window; self.root = root
            touches = ProbePhysicalTouches()
            window.addGestureRecognizer(touches)
        }
    }

    private let registry: ProbeSceneRegistry
    private var entries: [String: Entry] = [:]
    private let events: ProbePhysicalOperationEventLedger?
    // Retain original objects only for this opt-in profile, until process cleanup.
    // This prevents address reuse from masquerading as an unchanged owner.
    private var retainedOwners: [String: [AnyObject]] = [:]
    private var presentations: [String: ProbeScenePresentation] = [:]
    private var resizeStates: [String: Bool] = [:]
    private(set) var failure: String?
    init(registry: ProbeSceneRegistry, recordsContinuity: Bool = false) {
        self.registry = registry
        self.events = recordsContinuity ? .init() : nil
        if recordsContinuity {
            registry.operationChangeObserver = { [weak self] handle, kind in
                self?.events?.record("registry-" + kind, scene: handle.logicalSceneID)
            }
        }
    }

    func observe(window: UIWindow) {
        guard events != nil, let pair = entries.first(where: { $0.value.window === window }) else { return }
        let label = pair.key, entry = pair.value, value = ProbeScenePresentation.capture(window: window)
        if let previous = presentations[label], previous != value { events?.record("reader-presentation", scene: label) }
        presentations[label] = value
        if entry.root !== window.rootViewController { failure = failure ?? "Operation root replaced" }
    }

    func observeResize(scene: String, resizing: Bool) {
        guard let events else { return }
        // Even start/end delivered between snapshots remain in this history.
        if resizeStates[scene] != resizing { events.record(resizing ? "resize-began" : "resize-ended", scene: scene) }
        resizeStates[scene] = resizing
    }

    @discardableResult
    func install(window: UIWindow, handle: ProbeSceneHandle) -> String? {
        if let failure { return failure }
        guard ["scene-A", "scene-B"].contains(handle.logicalSceneID),
              registry.window(for: handle) === window, let root = window.rootViewController else {
            if let entry = entries[handle.logicalSceneID] { entry.window?.removeGestureRecognizer(entry.touches) }
            failure = "input observer requires an exact registered owner"; return failure
        }
        if let entry = entries[handle.logicalSceneID] {
            guard entry.handle == handle, entry.window === window, entry.root === root,
                  entry.touches.view === window, entry.touches.isEnabled else {
                entry.window?.removeGestureRecognizer(entry.touches)
                failure = "input observer owner replaced or detached"; return failure
            }
        } else {
            entries[handle.logicalSceneID] = Entry(handle: handle, window: window, root: root)
            if let events, let scene = window.windowScene {
                retainedOwners[handle.logicalSceneID] = [window, root, scene]
                events.install(.init(logicalSceneID: handle.logicalSceneID, nativeSceneID: handle.nativeSceneID,
                    generation: handle.disconnectGeneration, sceneIdentity: Self.identity(scene),
                    windowIdentity: Self.identity(window), rootIdentity: Self.identity(root)))
            }
        }
        observe(window: window)
        return nil
    }

    private static func identity(_ value: AnyObject) -> String { String(describing: ObjectIdentifier(value)) }
    private static func geometry(_ value: CGRect) -> ProbeGeometry {
        .init(x: value.origin.x, y: value.origin.y, width: value.width, height: value.height)
    }
    private static func transitioning(_ root: UIViewController) -> Bool {
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        while let current = pending.popLast() {
            guard visited.insert(ObjectIdentifier(current)).inserted else { continue }
            if current.transitionCoordinator != nil || current.isBeingPresented || current.isBeingDismissed { return true }
            pending.append(contentsOf: current.children)
            if let presented = current.presentedViewController { pending.append(presented) }
        }
        return false
    }

    func snapshot() -> ProbePhysicalInputSnapshot {
        var scenes: [ProbePhysicalSceneObservation] = []
        var input: [ProbePhysicalInputWindow] = []
        for label in ["scene-A", "scene-B"] {
            guard let entry = entries[label] else { continue }
            guard let window = entry.window, let root = window.rootViewController, let scene = window.windowScene else {
                failure = failure ?? "original input window, root or scene disappeared"
                continue
            }
            observe(window: window)
            let matches = registry.handle(logicalSceneID: label) == entry.handle
                && registry.window(for: entry.handle) === window && entry.root === root
                && entry.handle.nativeSceneID == scene.session.persistentIdentifier
            let attached = entry.touches.view === window
                && window.gestureRecognizers?.contains(where: { $0 === entry.touches }) == true
            if !matches || !attached || !entry.touches.isEnabled { failure = failure ?? "input observer owner changed" }
            scenes.append(.init(logicalSceneID: label, nativeSceneID: scene.session.persistentIdentifier,
                generation: entry.handle.disconnectGeneration,
                connected: matches && UIApplication.shared.connectedScenes.contains(scene),
                activationState: ProbeSceneActivationState(scene.activationState).rawValue,
                hidden: window.isHidden, alpha: Double(window.alpha), geometry: Self.geometry(window.frame),
                windowIdentity: Self.identity(window), rootIdentity: Self.identity(root)))
            input.append(.init(logicalSceneID: label, nativeSceneID: scene.session.persistentIdentifier,
                generation: entry.handle.disconnectGeneration, windowIdentity: Self.identity(window),
                rootIdentity: Self.identity(root), observerIdentity: Self.identity(entry.touches), attached: attached,
                enabled: entry.touches.isEnabled, reliable: entry.touches.ledger.reliable,
                touches: entry.touches.ledger.active.count, revision: entry.touches.ledger.revision,
                mounted: root.viewIfLoaded?.window === window, transitioning: Self.transitioning(root),
                resizing: scene.effectiveGeometry.isInteractivelyResizing))
        }
        let connected = UIApplication.shared.connectedScenes
        let inventory = connected.compactMap { $0 as? UIWindowScene }.map { scene in
            ProbePhysicalSceneInventory(nativeSceneID: scene.session.persistentIdentifier,
                activationState: ProbeSceneActivationState(scene.activationState).rawValue,
                keyWindowIdentity: scene.keyWindow.map(Self.identity), geometry: Self.geometry(scene.effectiveGeometry.coordinateSpace.bounds),
                screenGeometry: Self.geometry(scene.screen.bounds), windows: scene.windows.map { window in
                    ProbePhysicalWindowInventory(identity: Self.identity(window), rootIdentity: window.rootViewController.map(Self.identity),
                        fixtureOwner: entries.first(where: { $0.value.window === window })?.key,
                        sceneMatches: window.windowScene === scene, key: window.isKeyWindow,
                        hidden: window.isHidden, alpha: Double(window.alpha),
                        mounted: window.rootViewController?.viewIfLoaded?.window === window, geometry: Self.geometry(window.frame))
                }.sorted { $0.identity < $1.identity })
        }.sorted { $0.nativeSceneID < $1.nativeSceneID }
        return .init(scenes: scenes, input: input,
                     connectedSceneIDs: connected.map { $0.session.persistentIdentifier }.sorted(),
                     applicationActive: UIApplication.shared.applicationState == .active, inventory: inventory, failure: failure,
                     continuity: events?.snapshot())
    }
}

internal struct ProbePhysicalInputRequest: Codable, Equatable {
    let runID: String
    let processID: Int32
    let profile: ProbePhysicalOperationProfile
    let phase: String
    let nonce: String
    var setupProfile: ProbePhysicalOperationSetupProfile? = nil
}

internal struct ProbePhysicalInputCapture: Codable {
    let request: ProbePhysicalInputRequest
    let requestSHA256: String
    let captureID: String
    let before: ProbePhysicalInputSnapshot
    let after: ProbePhysicalInputSnapshot
    let idleFailure: String?
}

/// Pure handoff contract; file transport and host release/display/binary proof
/// remain separate. A valid input response alone never authorizes SDK work.
@MainActor
internal final class ProbePhysicalInputExchange {
    enum Rejection: Error { case request, reused, consumed }
    private let runID: String
    private let processID: Int32
    private let profile: ProbePhysicalOperationProfile
    private let setupProfile: ProbePhysicalOperationSetupProfile?
    private var consumedNonces = Set<String>()
    private var pendingSetup: (String, ProbePhysicalInputCapture)?
    private var admitted = false

    init(runID: String, processID: Int32, profile: ProbePhysicalOperationProfile,
         setupProfile: ProbePhysicalOperationSetupProfile? = nil) {
        self.runID = runID; self.processID = processID; self.profile = profile
        self.setupProfile = setupProfile
    }
    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func capture(request raw: Data, observe: () -> ProbePhysicalInputSnapshot) throws -> Data {
        do {
            return try makeCapture(request: raw, observe: observe)
        } catch {
            pendingSetup = nil
            admitted = true
            throw error
        }
    }

    private func makeCapture(request raw: Data, observe: () -> ProbePhysicalInputSnapshot) throws -> Data {
        guard raw.count <= 16_384, let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              Set(object.keys) == Set(["runID", "processID", "profile", "phase", "nonce"]
                + (setupProfile == nil ? [] : ["setupProfile"])),
              let nested = object["profile"] as? [String: Any],
              Set(nested.keys) == ["sourceRevision", "buildConfiguration", "scenarioSHA256", "inference"] else { throw Rejection.request }
        let request = try JSONDecoder().decode(ProbePhysicalInputRequest.self, from: raw)
        guard request.runID == runID, request.processID == processID, request.profile == profile,
              request.setupProfile == setupProfile,
              setupProfile.map(ProbePhysicalOperationSetupProfile.accepts) ?? true,
              ["setup", "cleanup"].contains(request.phase), UUID(uuidString: request.nonce) != nil else { throw Rejection.request }
        guard consumedNonces.insert(request.nonce).inserted else { throw Rejection.reused }
        guard request.phase != "setup" || (!admitted && pendingSetup == nil) else { throw Rejection.consumed }
        let before = observe(), after = observe()
        let failure = before.idleFailure() ?? after.idleFailure()
            ?? (before == after ? nil : "native input or window inventory changed during capture")
        let value = ProbePhysicalInputCapture(request: request, requestSHA256: Self.sha(raw), captureID: UUID().uuidString,
                                              before: before, after: after, idleFailure: failure)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        if request.phase == "setup" { pendingSetup = (Self.sha(bytes), value) }
        else { pendingSetup = nil; admitted = true }
        return bytes
    }

    func invalidateSetup() {
        pendingSetup = nil
        admitted = true
    }

    func consumeSetup(responseSHA256: String, live: ProbePhysicalInputSnapshot) -> String? {
        guard !admitted, let (digest, value) = pendingSetup else { return "setup capture absent or already consumed" }
        pendingSetup = nil
        admitted = true
        guard digest == responseSHA256 else { return "setup response digest differs" }
        if let reason = value.idleFailure ?? live.idleFailure() { return reason }
        guard value.after == live else {
            return "native input or window inventory changed since capture"
        }
        return nil
    }
}


internal struct ProbePhysicalOperationChannelIdentity: Codable, Equatable {
    let schemaVersion: Int
    let runID: String
    let processID: Int32
    let profile: ProbePhysicalOperationProfile
    let challengeID: String
    let installedCodeSHA256: String
    let executionArmed: Bool
    var setupProfile: ProbePhysicalOperationSetupProfile? = nil
}

internal struct ProbePhysicalOperationMessage: Codable {
    let schemaVersion: Int
    let runID: String
    let processID: Int32
    let challengeID: String
    let commandID: String
    let inputRequest: Data
}

internal struct ProbePhysicalOperationReply: Codable {
    let identity: ProbePhysicalOperationChannelIdentity
    let requestSHA256: String
    let commandID: String?
    let capture: Data?
    let rejection: String?
}

/// Fixture-only file channel. A completed content-addressed request is consumed
/// once; a reply is published atomically before the next poll. It captures input
/// only: neither successful transport nor a cleanup response authorizes SDK work.
@MainActor
internal final class ProbePhysicalOperationChannel {
    enum Mode {
        case historical
        case physicalSetup(ProbePhysicalOperationSetupProfile)
    }
    enum Failure: Error { case identity, file, message, reused, invalidated }
    let identity: ProbePhysicalOperationChannelIdentity
    private let directory: URL
    private let exchange: ProbePhysicalInputExchange
    private let observe: () -> ProbePhysicalInputSnapshot
    private let prepareCleanup: () -> Void
    private var lastPublication: String?
    private var consumedPublications = Set<String>()
    private var consumedCommands = Set<String>()
    private(set) var failure: String?
    private let publish: (Data, URL) throws -> Void
    nonisolated static let maximumBytes = 65_536

    init(runID: String, processID: Int32, profile: ProbePhysicalOperationProfile,
         installedCode: Data, directory: URL, observe: @escaping () -> ProbePhysicalInputSnapshot,
         publish: ((Data, URL) throws -> Void)? = nil, mode: Mode = .historical,
         prepareCleanup: @escaping () -> Void = {}) throws {
        let setupProfile: ProbePhysicalOperationSetupProfile?
        switch mode {
        case .historical: setupProfile = nil
        case .physicalSetup(let value):
            guard ProbePhysicalOperationSetupProfile.accepts(value),
                  let original = ProbeScenarioCatalog.scenario(identifier: ProbePhysicalOperationProfile.scenarioID),
                  profile == ProbePhysicalOperationProfile.make(scenario: original,
                    sourceRevision: profile.sourceRevision, buildConfiguration: profile.buildConfiguration) else {
                throw Failure.identity
            }
            setupProfile = value
        }
        guard runID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, processID > 0,
              installedCode.count <= Self.maximumBytes,
              profile.sourceRevision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              profile.buildConfiguration == "Debug", Self.digest(profile.scenarioSHA256),
              profile.inference == ProbePhysicalOperationProfile.inferenceMechanism,
              let code = try JSONSerialization.jsonObject(with: installedCode) as? [String: Any],
              code["runID"] as? String == runID, code["processID"] as? Int32 == processID,
              code["sourceRevision"] as? String == profile.sourceRevision,
              code["boundary"] as? String == "before-sdk-initialization",
              let binaries = code["binaries"] as? [String: String], !binaries.isEmpty,
              binaries.values.allSatisfy(Self.digest) else { throw Failure.identity }
        self.identity = .init(schemaVersion: setupProfile == nil ? 1 : 2,
                              runID: runID, processID: processID, profile: profile,
                              challengeID: UUID().uuidString, installedCodeSHA256: ProbePhysicalInputExchange.sha(installedCode),
                              executionArmed: false, setupProfile: setupProfile)
        self.directory = directory
        self.exchange = .init(runID: runID, processID: processID, profile: profile, setupProfile: setupProfile)
        self.observe = observe
        self.prepareCleanup = prepareCleanup
        self.publish = publish ?? Self.writeNew
        try self.publish(Self.encode(identity), url("challenge.json"))
    }

    func invalidateSetup(_ reason: String) {
        failure = failure ?? reason
        exchange.invalidateSetup()
    }

    func sealSetup() { exchange.invalidateSetup() }

    func consumeSetup(captureSHA256: String, live: ProbePhysicalInputSnapshot) -> String? {
        guard failure == nil, identity.schemaVersion == 2 else { return "Operation channel cannot admit setup" }
        return exchange.consumeSetup(responseSHA256: captureSHA256, live: live)
    }

    func readArtifact(_ suffix: String, limit: Int = maximumBytes) throws -> Data? {
        try read(url(suffix), limit: limit)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func digest(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }

    private static func writeNew(_ bytes: Data, _ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.file }
        try bytes.write(to: url, options: .atomic)
    }

    func url(_ suffix: String) -> URL { directory.appendingPathComponent(identity.runID + ".operations-" + suffix) }

    private func read(_ url: URL, limit: Int) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit else { throw Failure.file }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = try file.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw Failure.file }
        return bytes
    }

    /// Partial/missing publication is pending, never an invitation to reuse an
    /// earlier response. The caller owns a fixed operational deadline.
    @discardableResult
    func poll() throws -> ProbePhysicalOperationReply? {
        do { return try readPublication() }
        catch {
            failure = failure ?? "Operation channel file or response publication failed"
            throw error
        }
    }

    private func readPublication() throws -> ProbePhysicalOperationReply? {
        guard let marker = try read(url("request"), limit: 64),
              let selected = String(data: marker, encoding: .utf8), Self.digest(selected) else { return nil }
        if selected == lastPublication { return nil }
        guard let bytes = try read(url("request-" + selected + ".json"), limit: Self.maximumBytes),
              ProbePhysicalInputExchange.sha(bytes) == selected else { return nil }
        lastPublication = selected
        guard consumedPublications.insert(selected).inserted else {
            failure = "Operation publication reused"
            throw Failure.reused
        }
        guard !FileManager.default.fileExists(atPath: url("response-" + selected + ".json").path) else {
            throw Failure.file
        }
        var commandID: String?
        var capture: Data?
        var rejection: String?
        do {
            let message = try JSONDecoder().decode(ProbePhysicalOperationMessage.self, from: bytes)
            // Canonical outer bytes reject unknown/duplicate fields as well as
            // alternate encodings. The opaque inner request is preserved verbatim.
            guard try Self.encode(message) == bytes, message.schemaVersion == identity.schemaVersion,
                  message.runID == identity.runID, message.processID == identity.processID,
                  message.challengeID == identity.challengeID, UUID(uuidString: message.commandID) != nil else {
                throw Failure.message
            }
            commandID = message.commandID
            guard consumedCommands.insert(message.commandID).inserted else { throw Failure.reused }
            let request = try JSONDecoder().decode(ProbePhysicalInputRequest.self, from: message.inputRequest)
            guard try Self.encode(request) == message.inputRequest else { throw Failure.message }
            guard failure == nil || request.phase == "cleanup" else { throw Failure.invalidated }
            if request.phase == "cleanup", identity.schemaVersion == 2 {
                // The exchange alone cannot stop an already-consumed admission.
                invalidateSetup("cleanup requested")
                prepareCleanup()
            }
            capture = try exchange.capture(request: message.inputRequest, observe: observe)
        } catch {
            failure = failure ?? "Operation channel request rejected"
            rejection = "Operation channel request rejected"
        }
        let reply = ProbePhysicalOperationReply(identity: identity, requestSHA256: selected,
                                                commandID: commandID, capture: capture, rejection: rejection)
        try publish(Self.encode(reply), url("response-" + selected + ".json"))
        return reply
    }
}

/// Opt-in physical arrangement variant. The original Operation profile is an
/// unchanged source/inference contract; this namespace binds the new setup.
internal struct ProbePhysicalOperationSetupProfile: Codable, Equatable {
    static let scenarioID = "operations.cross-scene.physical-setup"
    static let variantID = "post-arrangement-owners-v1"
    static let setupBoundary = 4
    static let completed = "physical-operations-owners-verified"
    static let guardInterval = 4...21

    let variant: String
    let scenario: String
    let fullScenarioSHA256: String
    let setupPrefixSHA256: String
    let setupBoundaryIndex: Int
    let firstOperationIndex: Int
    let lastOperationIndex: Int
    let ownerBindingVersion: Int

    static var steps: [ProbeStep] {
        let original = ProbePhysicalOperationProfile.steps
        return [original[0], original[1], original[3], original[4],
                .init(.emitSceneContextMarker, scene: "scene-A", value: "operation-arranged-home-a"),
                .init(.emitSceneContextMarker, scene: "scene-B", value: "operation-arranged-home-b")]
            + Array(original[6...21])
    }

    static func make(scenario: ProbeScenario) -> Self? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard scenario.identifier == scenarioID,
              scenario == ProbeScenarioCatalog.scenario(identifier: scenarioID),
              scenario.steps == steps,
              !ProbeScenarioCatalog.usesExplicitOperationViewTargetSPI(scenario),
              let full = try? encoder.encode(scenario),
              let prefix = try? encoder.encode(Array(steps.prefix(6))) else { return nil }
        return .init(variant: variantID, scenario: scenarioID,
                     fullScenarioSHA256: SHA256.hash(data: full).map { String(format: "%02x", $0) }.joined(),
                     setupPrefixSHA256: SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined(),
                     setupBoundaryIndex: setupBoundary, firstOperationIndex: 6,
                     lastOperationIndex: 21, ownerBindingVersion: 1)
    }

    static func accepts(_ value: Self) -> Bool {
        guard let scenario = ProbeScenarioCatalog.scenario(identifier: scenarioID),
              let expected = make(scenario: scenario) else { return false }
        return value == expected
    }
}

/// A direct SDK scene-context read, distinct from marker attributes. The app
/// adapter must use the session-aware snapshot overload and its registered scene.
internal struct ProbePhysicalOperationRUMOwner: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let applicationID: String
    let sessionID: String
    let viewID: String
    let viewName: String
    let viewURL: String
}

/// Pure evidence binding. This does not consume a host admission or authorize
/// SDK work; the caller must preserve its actual direct reads and input capture.
internal struct ProbePhysicalOperationOwners: Codable, Equatable {
    let runID: String
    let processID: Int32
    let profile: ProbePhysicalOperationSetupProfile
    let setupCaptureSHA256: String
    let applicationID: String
    let service: String
    let source: String
    let input: ProbePhysicalInputSnapshot
    let contexts: [String: ProbePhysicalOperationRUMOwner]
    let mapperSnapshots: [String: ProbeSignal]

    private static func uuid(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    @MainActor
    static func bind(runID: String, processID: Int32, profile: ProbePhysicalOperationSetupProfile,
                     setupCaptureSHA256: String, applicationID: String,
                     before: ProbePhysicalInputSnapshot, after: ProbePhysicalInputSnapshot,
                     directBefore: [String: ProbePhysicalOperationRUMOwner],
                     directAfter: [String: ProbePhysicalOperationRUMOwner], signals: [ProbeSignal]) -> Self? {
        guard ProbePhysicalOperationSetupProfile.accepts(profile),
              runID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, processID > 0,
              setupCaptureSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              uuid(applicationID), before == after, after.idleFailure() == nil,
              directBefore == directAfter, Set(directAfter.keys) == ["scene-A", "scene-B"],
              Set(directAfter.values.map(\.viewID)).count == 2,
              Set(directAfter.values.map(\.sessionID)).count == 1,
              signals.allSatisfy({ $0.runID == runID && $0.scenarioID == profile.scenario && $0.sequence > 0 }),
              Set(signals.map(\.sequence)).count == signals.count else { return nil }
        var snapshots: [String: ProbeSignal] = [:]
        for scene in ["scene-A", "scene-B"] {
            guard let context = directAfter[scene], context.logicalSceneID == scene,
                  context.applicationID == applicationID, uuid(context.sessionID), uuid(context.viewID),
                  context.viewName == "ProbeHomeView", !context.viewURL.isEmpty,
                  let native = after.scenes.first(where: { $0.logicalSceneID == scene }),
                  context.nativeSceneID == native.nativeSceneID else { return nil }
            let views = signals.filter { $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == context.viewID }
            // Document versions choose current state; mapper delivery order and
            // occurrence numbers do not. All observations retain their raw IDs.
            guard !views.isEmpty, views.allSatisfy({
                $0.evidenceSource == .rumMapper && $0.semanticContext?.logicalSceneID == scene
                    && $0.semanticContext?.nativeSceneID == context.nativeSceneID && $0.semanticContext?.screen == "home"
                    && $0.rumContext?.sessionID == context.sessionID && $0.rumContext?.viewName == context.viewName
                    && $0.rumContext?.viewURL == context.viewURL && ($0.rumContext?.viewDocumentVersion ?? 0) > 0
            }), let latest = views.max(by: { ($0.rumContext?.viewDocumentVersion ?? 0) < ($1.rumContext?.viewDocumentVersion ?? 0) }),
                  latest.rumContext?.viewActive == true,
                  views.filter({ $0.rumContext?.viewDocumentVersion == latest.rumContext?.viewDocumentVersion })
                    .allSatisfy({ $0.rumContext == latest.rumContext && $0.semanticContext == latest.semanticContext }) else { return nil }
            snapshots[scene] = latest
        }
        return .init(runID: runID, processID: processID, profile: profile, setupCaptureSHA256: setupCaptureSHA256,
                     applicationID: applicationID, service: "ios-sdk-native-multi-scene-probe", source: "ios",
                     input: after, contexts: directAfter, mapperSnapshots: snapshots)
    }

    func markerFailure(_ name: String, scene: String, kind: ProbeSignalKind, signals: [ProbeSignal]) -> String? {
        let rows = signals.filter { $0.kind == kind && $0.name == name }
        guard rows.count == 1, let row = rows.first, let owner = contexts[scene],
              row.runID == runID, row.scenarioID == profile.scenario, row.evidenceSource == .rumMapper,
              row.sourceContext?.logicalSceneID == scene, row.sourceContext?.nativeSceneID == owner.nativeSceneID,
              row.sourceContext?.screen == "home", row.sourceContext?.phase == name,
              row.rumContext?.sessionID == owner.sessionID, row.rumContext?.viewID == owner.viewID,
              row.rumContext?.viewName == owner.viewName, row.rumContext?.viewURL == owner.viewURL,
              let eventID = row.eventID, Self.uuid(eventID) else { return "missing, duplicate or foreign Operation marker owner" }
        if kind == .rumAction {
            guard row.action?.id == eventID, row.action?.type == "custom",
                  row.action?.target == "probe-lifecycle-" + scene + ".home." + name else { return "Operation marker Action differs" }
        } else if kind == .rumResource {
            guard row.resource?.id == eventID, row.resource?.statusCode == 200,
                  row.resource?.type == "other", row.resource?.size == 1,
                  row.resource?.url == "https://multi-scene-probe.invalid/native/" + scene + "/home/" + name else {
                return "Operation marker Resource differs"
            }
        } else { return "unsupported Operation marker family" }
        return nil
    }

    /// Complete local identity checks. Native call assertions are not Operation
    /// vitals; raw/reduced backend ownership remains independently mandatory.
    func workFailure(signals: [ProbeSignal]) -> String? {
        guard signals.allSatisfy({ $0.runID == runID && $0.scenarioID == profile.scenario && $0.sequence > 0 }),
              Set(signals.map(\.sequence)).count == signals.count else { return "foreign or duplicated local signal identity" }
        let markers = ProbePhysicalOperationSetupProfile.steps.filter { $0.kind == .emitSceneContextMarker }
        let names = Set(markers.compactMap(\.value))
        let rows = signals.filter { [.rumAction, .rumResource].contains($0.kind) && ($0.name?.hasPrefix("operation-") ?? false) }
        guard rows.count == 20, rows.allSatisfy({ names.contains($0.name ?? "") }),
              Set(rows.compactMap(\.eventID)).count == 20 else { return "incomplete, duplicate or foreign marker inventory" }
        for marker in markers {
            guard let name = marker.value, let scene = marker.scene else { return "marker profile missing" }
            for kind in [ProbeSignalKind.rumAction, .rumResource] {
                if let reason = markerFailure(name, scene: scene, kind: kind, signals: signals) { return reason }
            }
        }
        let calls = ProbePhysicalOperationSetupProfile.steps.filter { [.startOperation, .succeedOperation, .failOperation].contains($0.kind) }
        let invoked = signals.filter { $0.operation != nil }.sorted { $0.sequence < $1.sequence }
        guard invoked.count == calls.count else { return "incomplete native Operation invocation inventory" }
        for (call, row) in zip(calls, invoked) {
            guard let scene = call.scene, let owner = contexts[scene], let instance = call.value,
                  row.kind == .assertion, row.evidenceSource == .probe, row.result == .pass,
                  row.stepKind == call.kind, row.semanticContext?.logicalSceneID == scene,
                  row.semanticContext?.nativeSceneID == owner.nativeSceneID, row.semanticContext?.screen == "home",
                  row.operation?.name == "multi_scene_probe_navigation", row.operation?.key == runID + "-" + instance,
                  row.operation?.step == (call.kind == .startOperation ? "start" : call.kind == .succeedOperation ? "succeed" : "fail"),
                  row.operation?.failureReason == (call.kind == .failOperation ? "error" : nil) else {
                return "native Operation invocation owner or order differs"
            }
        }
        return nil
    }

    @MainActor
    struct Progress {
        let owners: ProbePhysicalOperationOwners
        private(set) var nextIndex = ProbePhysicalOperationSetupProfile.setupBoundary
        private(set) var expectsAfter = false
        private(set) var failure: String?
        private(set) var complete = false

        mutating func observe(input: ProbePhysicalInputSnapshot, contexts: [String: ProbePhysicalOperationRUMOwner]) -> String? {
            if failure == nil && (input.idleFailure() != nil || input != owners.input || contexts != owners.contexts) {
                failure = "Operation input, topology or current RUM owner changed"
            }
            return failure
        }

        mutating func check(index: Int, step: ProbeStep, after: Bool, input: ProbePhysicalInputSnapshot,
                            contexts: [String: ProbePhysicalOperationRUMOwner], signals: [ProbeSignal]) -> String? {
            if let reason = observe(input: input, contexts: contexts) { return reason }
            guard !complete, index == nextIndex, after == expectsAfter,
                  ProbePhysicalOperationSetupProfile.guardInterval.contains(index),
                  step == ProbePhysicalOperationSetupProfile.steps[index] else {
                failure = "Operation setup/critical step is duplicate, late or changed"; return failure
            }
            if after && step.kind == .emitSceneContextMarker, let name = step.value, let scene = step.scene {
                if let reason = owners.markerFailure(name, scene: scene, kind: .rumAction, signals: signals) {
                    failure = reason; return reason
                }
            }
            return advance(index: index, after: after)
        }

        /// Native execution does not wait for a mapper at each step. The caller
        /// must require workFailure on the complete retained inventory at the end.
        mutating func checkBoundary(index: Int, step: ProbeStep, after: Bool, input: ProbePhysicalInputSnapshot,
                                    contexts: [String: ProbePhysicalOperationRUMOwner]) -> String? {
            if let reason = observe(input: input, contexts: contexts) { return reason }
            guard !complete, index == nextIndex, after == expectsAfter,
                  ProbePhysicalOperationSetupProfile.guardInterval.contains(index),
                  step == ProbePhysicalOperationSetupProfile.steps[index] else {
                failure = "Operation setup/critical step is duplicate, late or changed"; return failure
            }
            return advance(index: index, after: after)
        }

        private mutating func advance(index: Int, after: Bool) -> String? {
            if after { complete = index == 21; nextIndex += 1 }
            expectsAfter = !after
            return nil
        }
    }
}

#if DEBUG
/// Values returned by the SDK, without filling absent fields from mapper data.
internal struct ProbePhysicalOperationSDKValue: Codable, Equatable {
    let applicationID: String
    let sessionID: String
    let viewID: String?
    let viewName: String?
    let viewURL: String?
}

internal struct ProbePhysicalOperationSDKRead: Codable, Equatable {
    let logicalSceneID: String
    let targetNativeSceneID: String
    let value: ProbePhysicalOperationSDKValue?
}

internal struct ProbePhysicalOperationContextSample: Codable, Equatable {
    let sampledAt: Date
    let before: ProbePhysicalInputSnapshot
    let after: ProbePhysicalInputSnapshot
    let reads: [ProbePhysicalOperationSDKRead]
    let failure: String?

    @MainActor
    init(sampledAt: Date, before: ProbePhysicalInputSnapshot, after: ProbePhysicalInputSnapshot,
         reads: [ProbePhysicalOperationSDKRead]) {
        self.sampledAt = sampledAt; self.before = before; self.after = after; self.reads = reads
        failure = Self.validate(sampledAt: sampledAt, before: before, after: after, reads: reads)
    }

    @MainActor
    private static func validate(sampledAt: Date, before: ProbePhysicalInputSnapshot,
                                 after: ProbePhysicalInputSnapshot, reads: [ProbePhysicalOperationSDKRead]) -> String? {
        if let reason = before.idleFailure() ?? after.idleFailure() { return reason }
        guard before == after else { return "native input changed during SDK context reads" }
        guard sampledAt.timeIntervalSince1970.isFinite,
              reads.map(\.logicalSceneID) == ["scene-A", "scene-B"] else { return "SDK scene read inventory differs" }
        func uuid(_ value: String?) -> Bool {
            guard let value else { return false }
            return UUID(uuidString: value)?.uuidString.lowercased() == value
        }
        for read in reads {
            guard let scene = after.scenes.first(where: { $0.logicalSceneID == read.logicalSceneID }),
                  read.targetNativeSceneID == scene.nativeSceneID else { return "SDK read targets a different native scene" }
            guard let value = read.value else { return "current session-aware SDK scene context unavailable" }
            guard uuid(value.applicationID), uuid(value.sessionID), uuid(value.viewID),
                  value.viewName?.isEmpty == false, value.viewURL?.isEmpty == false else {
                return "current SDK scene context is incomplete"
            }
        }
        guard Set(reads.compactMap { $0.value?.applicationID }).count == 1,
              Set(reads.compactMap { $0.value?.sessionID }).count == 1,
              Set(reads.compactMap { $0.value?.viewID }).count == 2 else {
            return "SDK scene owners have different applications/sessions or aliased views"
        }
        return nil
    }

    /// Raw reads remain in the sample. This projection neither proves mapper
    /// delivery nor admits setup, SDK work, display readiness or cleanup.
    @MainActor
    var ownerProjection: [String: ProbePhysicalOperationRUMOwner]? {
        guard failure == nil, Self.validate(sampledAt: sampledAt, before: before, after: after, reads: reads) == nil else {
            return nil
        }
        var owners: [String: ProbePhysicalOperationRUMOwner] = [:]
        for read in reads {
            guard let value = read.value, let viewID = value.viewID,
                  let name = value.viewName, let url = value.viewURL else { return nil }
            owners[read.logicalSceneID] = .init(logicalSceneID: read.logicalSceneID, nativeSceneID: read.targetNativeSceneID,
                applicationID: value.applicationID, sessionID: value.sessionID, viewID: viewID, viewName: name, viewURL: url)
        }
        return owners
    }
}

/// Synchronous main-actor capture. The input sampler resolves registered native
/// scene/window/root identities; SDK reads always use that actual scene target.
@MainActor
internal final class ProbePhysicalOperationContextSampler {
    private let observeInput: () -> ProbePhysicalInputSnapshot
    private let readContext: (String, Date) -> ProbePhysicalOperationSDKValue?
    private let now: () -> Date


    init(observeInput: @escaping () -> ProbePhysicalInputSnapshot,
         readContext: @escaping (String, Date) -> ProbePhysicalOperationSDKValue?, now: @escaping () -> Date = Date.init) {
        self.observeInput = observeInput; self.readContext = readContext; self.now = now
    }

    func sample() -> ProbePhysicalOperationContextSample {
        let before = observeInput(), sampledAt = now()
        var reads: [ProbePhysicalOperationSDKRead] = []
        if before.idleFailure() == nil {
            for scene in before.scenes {
                reads.append(.init(logicalSceneID: scene.logicalSceneID, targetNativeSceneID: scene.nativeSceneID,
                                   value: readContext(scene.nativeSceneID, sampledAt)))
            }
        }
        return .init(sampledAt: sampledAt, before: before, after: observeInput(), reads: reads)
    }
}

/// The channel reply remains unchanged. This separate, versioned document keeps
/// the three actual observations and their acquisition order, including partial
/// failures. CAPTURED means persisted bytes, never SDK or teardown permission.
internal struct ProbePhysicalOperationContextRecord: Codable {
    let schemaVersion: Int
    let identity: ProbePhysicalOperationChannelIdentity
    let requestSHA256: String
    let replySHA256: String
    let captureSHA256: String
    let order: [String]
    let components: [String: Data]
    let componentSHA256: [String: String]
    let state: String
    let deadline: TimeInterval
    let finishedAt: TimeInterval
    let failure: String?

    @MainActor
    func ownerBinding(capture raw: Data) -> ProbePhysicalOperationOwners? {
        guard schemaVersion == 1, state == "CAPTURED", failure == nil,
              identity.schemaVersion == 2, !identity.executionArmed,
              let profile = identity.setupProfile,
              deadline.isFinite, finishedAt.isFinite, finishedAt < deadline,
              order == ["sdkBefore", "mapper", "sdkAfter"],
              Set(components.keys) == Set(order), Set(componentSHA256.keys) == Set(order),
              components.allSatisfy({ ProbePhysicalInputExchange.sha($0.value) == componentSHA256[$0.key] }),
              ProbePhysicalInputExchange.sha(raw) == captureSHA256,
              let capture = try? JSONDecoder().decode(ProbePhysicalInputCapture.self, from: raw),
              capture.request.phase == "setup", capture.idleFailure == nil,
              capture.request.runID == identity.runID, capture.request.processID == identity.processID,
              capture.request.profile == identity.profile, capture.request.setupProfile == profile,
              let beforeBytes = components["sdkBefore"], let mapperBytes = components["mapper"],
              let afterBytes = components["sdkAfter"],
              let first = try? JSONDecoder().decode(ProbePhysicalOperationContextSample.self, from: beforeBytes),
              let signals = try? JSONDecoder().decode([ProbeSignal].self, from: mapperBytes),
              let last = try? JSONDecoder().decode(ProbePhysicalOperationContextSample.self, from: afterBytes),
              let before = first.ownerProjection, let after = last.ownerProjection,
              capture.before == capture.after, capture.after == first.before,
              first.after == last.before, let applicationID = before["scene-A"]?.applicationID else { return nil }
        return ProbePhysicalOperationOwners.bind(runID: identity.runID, processID: identity.processID,
            profile: profile, setupCaptureSHA256: captureSHA256, applicationID: applicationID,
            before: first.before, after: last.after, directBefore: before, directAfter: after, signals: signals)
    }
}

internal struct ProbePhysicalOperationContextCompletion: Codable {
    let schemaVersion: Int
    let identity: ProbePhysicalOperationChannelIdentity
    let requestSHA256: String
    let replySHA256: String
    let captureSHA256: String
    let contextSHA256: String
    let status: Data
    let statusSHA256: String
    let state: String
    let deadline: TimeInterval
    let finishedAt: TimeInterval
}

/// Canonical identity-only envelope. Opaque host bytes keep their original
/// encoding; native joins are against this process's own retained observations.
internal struct ProbePhysicalOperationHostHandoff: Codable {
    let schemaVersion: Int
    let identity: ProbePhysicalOperationChannelIdentity
    let proof: Data
    let result: Data
}

/// The terminal receipt covers this immutable local interval. Host collection,
/// physical display, backend ownership and cleanup keep separate verdicts.
internal struct ProbePhysicalOperationLocalCompletion: Codable {
    let schemaVersion: Int
    let identity: ProbePhysicalOperationChannelIdentity
    let state: String
    let profile: String
    let deadline: TimeInterval
    let setupCaptureSHA256: String
    let hostPublicationSHA256: String
    let finalObservation: String
    let finalObservationSHA256: String
    let finalMapperSHA256: String
    let observationCount: Int
    let artifacts: [String: String]
}

@MainActor
internal final class ProbePhysicalOperationAdmission {
    enum Failure: Error { case proof, identity, capture, live, publication, sequence }
    private struct HostProof: Decodable {
        let schemaVersion: Int
        let kind: String
        let state: String
        let identity: ProbePhysicalOperationChannelIdentity
        let consumptionID: String
        let captureSHA256: String
        let contextSHA256: String
        let installedCodeSHA256: String
        let requestSHA256: String
        let replySHA256: String
        let completionSHA256: String
        let screenshotSHA256: String
        let reviewSHA256: String
        let releaseRequestSHA256: String
        let releaseSHA256: String
        let artifacts: [String: String]
        let deadline: TimeInterval
        let finishedAt: TimeInterval
        let sdkAdmitted: Bool
        let teardownAuthorized: Bool
    }
    private struct HostResult: Decodable {
        let state: String
        let proofSHA256: String
        let deadline: TimeInterval
        let finishedAt: TimeInterval
        let sdkAdmitted: Bool
        let teardownAuthorized: Bool
    }
    private struct Observation: Codable {
        let index: Int
        let boundary: String
        let sample: ProbePhysicalOperationContextSample
    }

    private let channel: ProbePhysicalOperationChannel
    private let deadline: TimeInterval
    private let sample: () -> ProbePhysicalOperationContextSample
    private let mapper: () -> [ProbeSignal]
    private let now: () -> TimeInterval
    private var checking = false
    private let wait: () async throws -> Void
    private var hostConsumed = false
    private var capture: Data?
    private var capturedContexts: [String: ProbePhysicalOperationRUMOwner]?
    private var progress: ProbePhysicalOperationOwners.Progress?
    private var invokedIndex: Int?
    private var observationSequence = 0
    private var persistedDigests: [String: String] = [:]
    private(set) var failure: String?
    private(set) var complete = false

    init(channel: ProbePhysicalOperationChannel, deadline: TimeInterval,
         sample: @escaping () -> ProbePhysicalOperationContextSample, mapper: @escaping () -> [ProbeSignal],
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         wait: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 500_000_000) }) throws {
        guard channel.identity.schemaVersion == 2, channel.identity.setupProfile != nil,
              deadline.isFinite, now() < deadline else { throw Failure.identity }
        self.channel = channel; self.deadline = deadline; self.sample = sample; self.mapper = mapper; self.now = now; self.wait = wait
        guard !FileManager.default.fileExists(atPath: channel.url("native-admission.json").path) else { throw Failure.publication }
    }

    private func persist<T: Encodable>(_ value: T, _ suffix: String) throws {
        let raw = try ProbePhysicalOperationChannel.encode(value), url = channel.url(suffix)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.publication }
        try raw.write(to: url, options: .atomic)
        guard try channel.readArtifact(suffix, limit: ProbePhysicalOperationCapturePump.maximumContextBytes) == raw else {
            throw Failure.publication
        }
        persistedDigests[suffix] = ProbePhysicalInputExchange.sha(raw)
    }
    private func live() throws {
        guard failure == nil, channel.failure == nil, !Task.isCancelled, now() < deadline else { throw Failure.live }
    }
    private func stop(_ reason: String) -> String {
        failure = failure ?? reason
        channel.invalidateSetup(failure!)
        // This failure receipt is evidence, never an extension of the deadline.
        try? persist(["state": "INVALID", "reason": failure!], "native-admission-failure.json")
        return failure!
    }
    private func observe(index: Int, boundary: String) throws -> ProbePhysicalOperationContextSample {
        try live()
        let value = sample()
        observationSequence += 1
        try persist(Observation(index: index, boundary: boundary, sample: value),
                    "native-observation-" + String(observationSequence) + ".json")
        try live()
        guard value.failure == nil, value.ownerProjection != nil else { throw Failure.live }
        return value
    }

    /// One host publication per process. Failure consumes it permanently.
    /// Called separately in controls; the app uses the hash-addressed file below.
    func consumeHost(_ raw: Data) throws {
        guard !hostConsumed else { _ = stop("host proof reused"); throw Failure.proof }
        hostConsumed = true
        do {
            try live()
            guard raw.count <= ProbePhysicalOperationCapturePump.maximumContextBytes else { throw Failure.proof }
            let handoff = try JSONDecoder().decode(ProbePhysicalOperationHostHandoff.self, from: raw)
            guard try ProbePhysicalOperationChannel.encode(handoff) == raw,
                  handoff.schemaVersion == 1, handoff.identity == channel.identity else { throw Failure.identity }
            try persist(handoff, "native-host-consumed.json")
            let proof = try JSONDecoder().decode(HostProof.self, from: handoff.proof)
            let result = try JSONDecoder().decode(HostResult.self, from: handoff.result)
            guard proof.schemaVersion == 1, proof.kind == "OPERATIONS_HOST_PREREQUISITES",
                  proof.state == "HOST_PROOF_PREPARED", result.state == proof.state,
                  proof.identity == channel.identity, UUID(uuidString: proof.consumptionID) != nil,
                  result.proofSHA256 == ProbePhysicalInputExchange.sha(handoff.proof),
                  proof.installedCodeSHA256 == channel.identity.installedCodeSHA256,
                  proof.deadline == deadline, result.deadline == deadline,
                  proof.finishedAt.isFinite, result.finishedAt.isFinite,
                  proof.finishedAt <= result.finishedAt, result.finishedAt < deadline,
                  !proof.sdkAdmitted, !proof.teardownAuthorized, !result.sdkAdmitted, !result.teardownAuthorized,
                  proof.artifacts.values.allSatisfy({ $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }) else {
                throw Failure.proof
            }
            for (name, digest) in ["installed-code.json": proof.installedCodeSHA256,
                "native-capture.json": proof.captureSHA256, "native-context.json": proof.contextSHA256,
                "native-request.json": proof.requestSHA256, "native-reply.json": proof.replySHA256,
                "native-context-result.json": proof.completionSHA256, "screen.png": proof.screenshotSHA256,
                "display-review.json": proof.reviewSHA256, "release-request.json": proof.releaseRequestSHA256,
                "release-ack.json": proof.releaseSHA256] {
                guard proof.artifacts[name] == digest else { throw Failure.proof }
            }
            guard proof.requestSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  let requestRaw = try channel.readArtifact("request-" + proof.requestSHA256 + ".json"),
                  ProbePhysicalInputExchange.sha(requestRaw) == proof.requestSHA256,
                  let replyRaw = try channel.readArtifact("response-" + proof.requestSHA256 + ".json"),
                  ProbePhysicalInputExchange.sha(replyRaw) == proof.replySHA256,
                  let contextRaw = try channel.readArtifact("context-" + proof.requestSHA256 + ".json",
                      limit: ProbePhysicalOperationCapturePump.maximumContextBytes),
                  ProbePhysicalInputExchange.sha(contextRaw) == proof.contextSHA256,
                  let terminalRaw = try channel.readArtifact("context-" + proof.requestSHA256 + "-result.json"),
                  ProbePhysicalInputExchange.sha(terminalRaw) == proof.completionSHA256 else { throw Failure.capture }
            let request = try JSONDecoder().decode(ProbePhysicalOperationMessage.self, from: requestRaw)
            let reply = try JSONDecoder().decode(ProbePhysicalOperationReply.self, from: replyRaw)
            let context = try JSONDecoder().decode(ProbePhysicalOperationContextRecord.self, from: contextRaw)
            let terminal = try JSONDecoder().decode(ProbePhysicalOperationContextCompletion.self, from: terminalRaw)
            guard try ProbePhysicalOperationChannel.encode(request) == requestRaw,
                  request.schemaVersion == channel.identity.schemaVersion, request.runID == channel.identity.runID,
                  request.processID == channel.identity.processID, request.challengeID == channel.identity.challengeID,
                  reply.identity == channel.identity, reply.rejection == nil,
                  reply.requestSHA256 == proof.requestSHA256, reply.commandID == request.commandID,
                  let rawCapture = reply.capture, ProbePhysicalInputExchange.sha(rawCapture) == proof.captureSHA256,
                  context.identity == channel.identity, context.state == "CAPTURED", context.failure == nil,
                  context.order == ["sdkBefore", "mapper", "sdkAfter"],
                  Set(context.components.keys) == Set(context.order), Set(context.componentSHA256.keys) == Set(context.order),
                  context.components.allSatisfy({ ProbePhysicalInputExchange.sha($0.value) == context.componentSHA256[$0.key] }),
                  context.replySHA256 == proof.replySHA256, context.captureSHA256 == proof.captureSHA256,
                  context.requestSHA256 == proof.requestSHA256, context.deadline == deadline,
                  terminal.identity == channel.identity, terminal.state == "CAPTURE_COMPLETE",
                  terminal.contextSHA256 == proof.contextSHA256, terminal.requestSHA256 == proof.requestSHA256,
                  terminal.replySHA256 == proof.replySHA256, terminal.captureSHA256 == proof.captureSHA256,
                  terminal.deadline == deadline, terminal.finishedAt < deadline,
                  ProbePhysicalInputExchange.sha(terminal.status) == terminal.statusSHA256,
                  let firstRaw = context.components["sdkBefore"], let lastRaw = context.components["sdkAfter"] else {
                throw Failure.capture
            }
            let first = try JSONDecoder().decode(ProbePhysicalOperationContextSample.self, from: firstRaw)
            let last = try JSONDecoder().decode(ProbePhysicalOperationContextSample.self, from: lastRaw)
            let input = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: rawCapture)
            guard input.request.phase == "setup", input.idleFailure == nil,
                  input.request.runID == channel.identity.runID, input.request.processID == channel.identity.processID,
                  input.request.profile == channel.identity.profile, input.request.setupProfile == channel.identity.setupProfile,
                  input.requestSHA256 == ProbePhysicalInputExchange.sha(request.inputRequest),
                  try ProbePhysicalOperationChannel.encode(input.request) == request.inputRequest,
                  input.before == input.after, input.after == first.before,
                  first.after == last.before, first.before == last.after,
                  let contexts = first.ownerProjection, contexts == last.ownerProjection,
                  first.after.continuity?.owners.count == 2 else { throw Failure.capture }
            capture = rawCapture; capturedContexts = contexts
        } catch { _ = stop("host proof or original native capture invalid"); throw error }
    }

    private func prepare() async throws {
        while !hostConsumed {
            try live()
            if let marker = try channel.readArtifact("host-publication", limit: 64),
               let digest = String(data: marker, encoding: .utf8),
               digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
               let raw = try channel.readArtifact("host-publication-" + digest + ".json",
                    limit: ProbePhysicalOperationCapturePump.maximumContextBytes),
               ProbePhysicalInputExchange.sha(raw) == digest { try consumeHost(raw); break }
            try await wait()
        }
        guard let capture, let contexts = capturedContexts, let setup = channel.identity.setupProfile else { throw Failure.capture }
        let original = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: capture)
        while progress == nil {
            let before = try observe(index: 4, boundary: "binding-before")
            let signals = mapper()
            try persist(signals, "native-mapper-binding-" + String(observationSequence) + ".json")
            let after = try observe(index: 4, boundary: "binding-after")
            guard before.before == original.after, before.after == after.before, after.after == original.after,
                  before.ownerProjection == contexts, after.ownerProjection == contexts else { throw Failure.live }
            if let owners = ProbePhysicalOperationOwners.bind(runID: channel.identity.runID, processID: channel.identity.processID,
                profile: setup, setupCaptureSHA256: ProbePhysicalInputExchange.sha(capture),
                applicationID: contexts["scene-A"]!.applicationID, before: before.before, after: after.after,
                directBefore: contexts, directAfter: contexts, signals: signals) {
                try persist(signals, "native-binding-mapper.json")
                guard channel.consumeSetup(captureSHA256: owners.setupCaptureSHA256, live: after.after) == nil else {
                    throw Failure.capture
                }
                try persist(owners, "native-admission.json")
                progress = .init(owners: owners)
            } else {
                // Only absence is pending. Contradictory owner evidence stops.
                let ids = Set(signals.filter { $0.kind == .rumViewSnapshot }.compactMap { $0.rumContext?.viewID })
                guard !Set(contexts.values.map(\.viewID)).isSubset(of: ids) else { throw Failure.capture }
                try await wait()
            }
        }
    }

    func check(index: Int, step: ProbeStep, after: Bool) async -> String? {
        guard index >= ProbePhysicalOperationSetupProfile.setupBoundary else { return nil }
        guard !checking else { return stop("reentrant Operation admission") }
        checking = true
        defer { checking = false }
        do {
            if progress == nil { guard index == 4 && !after else { throw Failure.sequence }; try await prepare() }
            let value = try observe(index: index, boundary: after ? "after" : "before")
            guard var state = progress, let contexts = value.ownerProjection,
                  !after || invokedIndex == index,
                  state.checkBoundary(index: index, step: step, after: after, input: value.after, contexts: contexts) == nil else {
                throw Failure.sequence
            }
            progress = state
            if after { invokedIndex = nil }
            if state.complete {
                while true {
                    let last = try observe(index: index, boundary: "collection")
                    guard state.observe(input: last.after, contexts: last.ownerProjection ?? [:]) == nil else { throw Failure.live }
                    let signals = mapper()
                    try persist(signals, "native-mapper-collection-" + String(observationSequence) + ".json")
                    if state.owners.workFailure(signals: signals) == nil {
                        try persist(signals, "native-final-mapper.json")
                        // Mapper collection and persistence may overlap a native
                        // notification. Seal only after a fresh continuity read.
                        let seal = try observe(index: index, boundary: "collection-seal")
                        guard state.observe(input: seal.after, contexts: seal.ownerProjection ?? [:]) == nil else {
                            throw Failure.live
                        }
                        let observation = "native-observation-" + String(observationSequence) + ".json"
                        guard let observationHash = persistedDigests[observation],
                              let mapperHash = persistedDigests["native-final-mapper.json"],
                              let hostHash = persistedDigests["native-host-consumed.json"] else { throw Failure.publication }
                        try persist(ProbePhysicalOperationLocalCompletion(schemaVersion: 1, identity: channel.identity,
                            state: "LOCAL_OWNERS_VERIFIED", profile: state.owners.profile.scenario, deadline: deadline,
                            setupCaptureSHA256: state.owners.setupCaptureSHA256, hostPublicationSHA256: hostHash,
                            finalObservation: observation, finalObservationSHA256: observationHash, finalMapperSHA256: mapperHash,
                            observationCount: observationSequence, artifacts: persistedDigests), "native-local-result.json")
                        complete = true; break
                    }
                    let rows = signals.filter { [.rumAction, .rumResource].contains($0.kind)
                        && ($0.name?.hasPrefix("operation-") ?? false) }
                    guard rows.count < 20 else { throw Failure.capture }
                    for marker in ProbePhysicalOperationSetupProfile.steps where marker.kind == .emitSceneContextMarker {
                        guard let name = marker.value, let scene = marker.scene else { throw Failure.capture }
                        for kind in [ProbeSignalKind.rumAction, .rumResource] where rows.contains(where: { $0.kind == kind && $0.name == name }) {
                            guard state.owners.markerFailure(name, scene: scene, kind: kind, signals: signals) == nil else {
                                throw Failure.capture
                            }
                        }
                    }
                    try await wait()
                }
            }
            return nil
        } catch { return stop("Operation setup, live ownership or final evidence incomplete") }
    }

    /// Called inside the executor after target resolution, immediately before
    /// its synchronous SDK work. A failed guard must skip the call/assertion.
    func authorize(_ step: ProbeStep) -> String? {
        do {
            guard var state = progress, state.expectsAfter, !state.complete, invokedIndex == nil,
                  step == ProbePhysicalOperationSetupProfile.steps[state.nextIndex] else { throw Failure.sequence }
            let value = try observe(index: state.nextIndex, boundary: "call")
            guard let contexts = value.ownerProjection,
                  state.observe(input: value.after, contexts: contexts) == nil else { throw Failure.live }
            progress = state; invokedIndex = state.nextIndex
            return nil
        } catch { return stop("Operation call rejected before SDK dispatch") }
    }
}

internal struct ProbePhysicalOperationCleanupReceipt: Codable {
    let schemaVersion: Int
    let identity: ProbePhysicalOperationChannelIdentity
    let requestSHA256: String
    let replySHA256: String
    let captureSHA256: String
    let contextCompletionSHA256: String
    let driver: ProbeScenarioDriver.CleanupState?
    let state: String
    let pumpStopped: Bool
    let pumpStopStatus: Data?
    let pumpStopStatusSHA256: String?
    let nativeLocalResultSHA256: String?
    let deadline: TimeInterval
    let finishedAt: TimeInterval
}

/// App-owned, opt-in capture only. The fixed deadline includes cleanup capture.
/// All observations and bounded file operations are serialized on MainActor;
/// asynchronous sleeps yield between polls. No Operation is dispatched here.
@MainActor
internal final class ProbePhysicalOperationCapturePump {
    enum Failure: Error { case deadline, file, identity, reentrant }
    private struct Status: Codable {
        let identity: ProbePhysicalOperationChannelIdentity
        let sequence: Int
        let state: String
        let requestSHA256: String?
        let deadline: TimeInterval
        let observedAt: TimeInterval
    }

    static let maximumContextBytes = 1_048_576
    let channel: ProbePhysicalOperationChannel
    let deadline: TimeInterval
    private let sample: () -> ProbePhysicalOperationContextSample
    private let mapper: () -> [ProbeSignal]
    private let now: () -> TimeInterval
    private let publish: (Data, URL) throws -> Void
    private let reportFailure: (String) -> Void
    private let cleanupState: () -> ProbeScenarioDriver.CleanupState?
    private var task: Task<Void, Never>?
    private var statusSequence = 0
    private var polling = false
    private var hasCompletedCapture = false
    private(set) var started = false
    private(set) var stopped = false
    private(set) var failure: String?
    private(set) var statusPublicationFailed = false

    init(channel: ProbePhysicalOperationChannel, deadline: TimeInterval,
         sample: @escaping () -> ProbePhysicalOperationContextSample, mapper: @escaping () -> [ProbeSignal],
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         publish: ((Data, URL) throws -> Void)? = nil, reportFailure: @escaping (String) -> Void = { _ in },
         cleanupState: @escaping () -> ProbeScenarioDriver.CleanupState? = { nil }) throws {
        guard channel.identity.schemaVersion == 2, channel.identity.setupProfile != nil,
              !channel.identity.executionArmed else { throw Failure.identity }
        guard deadline.isFinite, deadline > now() else { throw Failure.deadline }
        self.channel = channel; self.deadline = deadline; self.sample = sample; self.mapper = mapper
        self.now = now; self.publish = publish ?? Self.writeNew; self.reportFailure = reportFailure
        self.cleanupState = cleanupState
        try status("CREATED")
    }

    deinit { task?.cancel() }

    private static func writeNew(_ bytes: Data, _ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.file }
        try bytes.write(to: url, options: .atomic)
    }

    private func persist(_ bytes: Data, to url: URL) throws {
        guard bytes.count <= Self.maximumContextBytes,
              !FileManager.default.fileExists(atPath: url.path) else { throw Failure.file }
        try publish(bytes, url)
        guard try read(url) == bytes else { throw Failure.file }
    }

    private func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.maximumContextBytes else { throw Failure.file }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = try file.read(upToCount: Self.maximumContextBytes + 1) ?? Data()
        guard bytes.count <= Self.maximumContextBytes else { throw Failure.file }
        return bytes
    }

    private func live() throws {
        guard !stopped, now() < deadline else { throw Failure.deadline }
    }

    @discardableResult
    private func status(_ state: String, request: String? = nil) throws -> Data {
        statusSequence += 1
        let value = Status(identity: channel.identity, sequence: statusSequence, state: state,
                           requestSHA256: request, deadline: deadline, observedAt: now())
        let bytes = try ProbePhysicalOperationChannel.encode(value)
        try persist(bytes, to: channel.url("capture-status-" + String(statusSequence) + ".json"))
        return bytes
    }

    private func invalidate(_ reason: String, request: String? = nil) {
        failure = failure ?? reason
        channel.invalidateSetup(reason)
        do { try status(reason, request: request) }
        catch { statusPublicationFailed = true }
        reportFailure(reason)
    }

    func start() {
        guard !started, !stopped else { return }
        started = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.pollOnce() == true else { return }
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { self?.stop(); return }
            }
            self?.stop()
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        task?.cancel()
        channel.sealSetup()
        if polling || !hasCompletedCapture { invalidate("STOPPED") }
        else {
            do { try status("STOPPED_AFTER_CAPTURE") }
            catch { statusPublicationFailed = true; reportFailure("STOP_STATUS_FAILED") }
        }
    }

    /// Exposed to focused controls without a scheduler. A failed setup remains
    /// failed, but the same pump can still publish fresh cleanup input evidence.
    @discardableResult
    func pollOnce() -> Bool {
        guard !stopped else { return false }
        guard !polling else { invalidate("REENTRANT_POLL"); return false }
        polling = true
        defer { polling = false }
        do {
            try live()
            if let reply = try channel.poll() {
                try live()
                if let raw = reply.capture { capture(reply, raw: raw) }
                else { invalidate("REQUEST_REJECTED", request: reply.requestSHA256) }
            }
        } catch {
            if now() < deadline || !hasCompletedCapture || failure != nil {
                invalidate("CHANNEL_OR_DEADLINE_FAILED")
            }
        }
        if stopped { return false }
        if now() >= deadline {
            stopped = true
            channel.sealSetup()
            if hasCompletedCapture && failure == nil {
                do { try status("DEADLINE_AFTER_CAPTURE") }
                catch { statusPublicationFailed = true; reportFailure("STOP_STATUS_FAILED") }
            } else { invalidate("DEADLINE_EXPIRED") }
        }
        return !stopped
    }

    private func finishCleanup(reply: ProbePhysicalOperationReply, capture: Data,
                               completion: ProbePhysicalOperationContextCompletion) throws {
        try live()
        let driver = cleanupState()
        let quiescent = driver?.requested == true && driver?.stopped == true
        let local = try channel.readArtifact("native-local-result.json", limit: Self.maximumContextBytes)
        var stoppedStatus: Data?
        if quiescent {
            stopped = true
            task?.cancel()
            channel.sealSetup()
            stoppedStatus = try status("STOPPED_FOR_CLEANUP", request: reply.requestSHA256)
        }
        guard now() < deadline else { throw Failure.deadline }
        let receipt = ProbePhysicalOperationCleanupReceipt(schemaVersion: 1, identity: channel.identity,
            requestSHA256: reply.requestSHA256, replySHA256: completion.replySHA256,
            captureSHA256: ProbePhysicalInputExchange.sha(capture),
            contextCompletionSHA256: ProbePhysicalInputExchange.sha(try ProbePhysicalOperationChannel.encode(completion)),
            driver: driver, state: quiescent ? "STOPPED" : "NOT_STOPPED", pumpStopped: stopped,
            pumpStopStatus: stoppedStatus, pumpStopStatusSHA256: stoppedStatus.map(ProbePhysicalInputExchange.sha),
            nativeLocalResultSHA256: local.map(ProbePhysicalInputExchange.sha), deadline: deadline, finishedAt: now())
        try persist(ProbePhysicalOperationChannel.encode(receipt),
                    to: channel.url("cleanup-" + reply.requestSHA256 + "-driver.json"))
        guard now() < deadline else { throw Failure.deadline }
    }

    private func capture(_ reply: ProbePhysicalOperationReply, raw: Data) {
        let prefix = "context-" + reply.requestSHA256
        var components: [String: Data] = [:]
        var order: [String] = []
        var replyHash = ""
        func record(_ state: String, reason: String?) -> ProbePhysicalOperationContextRecord {
            .init(schemaVersion: 1, identity: channel.identity, requestSHA256: reply.requestSHA256,
                  replySHA256: replyHash, captureSHA256: ProbePhysicalInputExchange.sha(raw), order: order,
                  components: components, componentSHA256: components.mapValues(ProbePhysicalInputExchange.sha),
                  state: state, deadline: deadline, finishedAt: now(), failure: reason)
        }
        do {
            try live()
            let suffixes = [".json", "-result.json", "-accepted.json", "-sdkBefore.json", "-mapper.json", "-sdkAfter.json"]
            guard suffixes.allSatisfy({ !FileManager.default.fileExists(atPath: channel.url(prefix + $0).path) }) else {
                throw Failure.file
            }
            let replyBytes = try read(channel.url("response-" + reply.requestSHA256 + ".json"))
            replyHash = ProbePhysicalInputExchange.sha(replyBytes)
            guard try ProbePhysicalOperationChannel.encode(reply) == replyBytes else { throw Failure.file }
            try persist(replyBytes, to: channel.url(prefix + "-accepted.json"))
            try live()
            let first = sample()
            components["sdkBefore"] = try ProbePhysicalOperationChannel.encode(first); order.append("sdkBefore")
            try live()
            try persist(components["sdkBefore"]!, to: channel.url(prefix + "-sdkBefore.json"))
            try live()
            let signals = mapper()
            components["mapper"] = try ProbePhysicalOperationChannel.encode(signals); order.append("mapper")
            try live()
            try persist(components["mapper"]!, to: channel.url(prefix + "-mapper.json"))
            try live()
            let last = sample()
            components["sdkAfter"] = try ProbePhysicalOperationChannel.encode(last); order.append("sdkAfter")
            try live()
            try persist(components["sdkAfter"]!, to: channel.url(prefix + "-sdkAfter.json"))
            try live()
            if let input = try? JSONDecoder().decode(ProbePhysicalInputCapture.self, from: raw),
               input.request.phase == "setup", failure != nil || channel.failure != nil { throw Failure.reentrant }
            let contextBytes = try ProbePhysicalOperationChannel.encode(record("CAPTURED", reason: nil))
            try persist(contextBytes, to: channel.url(prefix + ".json"))
            try live()
            let statusBytes = try status("CONTEXT_PUBLISHED", request: reply.requestSHA256)
            try live()
            let completion = ProbePhysicalOperationContextCompletion(schemaVersion: 1, identity: channel.identity,
                requestSHA256: reply.requestSHA256, replySHA256: replyHash,
                captureSHA256: ProbePhysicalInputExchange.sha(raw), contextSHA256: ProbePhysicalInputExchange.sha(contextBytes),
                status: statusBytes, statusSHA256: ProbePhysicalInputExchange.sha(statusBytes), state: "CAPTURE_COMPLETE",
                deadline: deadline, finishedAt: now())
            try persist(ProbePhysicalOperationChannel.encode(completion), to: channel.url(prefix + "-result.json"))
            try live()
            hasCompletedCapture = true
            let input = try JSONDecoder().decode(ProbePhysicalInputCapture.self, from: raw)
            if input.request.phase == "cleanup" {
                try finishCleanup(reply: reply, capture: raw, completion: completion)
            }
        } catch {
            let reason = "CONTEXT_OR_DEADLINE_FAILED"
            invalidate(reason, request: reply.requestSHA256)
            // Failure evidence may be written after expiry; it never resumes work
            // or rewrites a completed/failed document from this request.
            do {
                try persist(ProbePhysicalOperationChannel.encode(record("INVALID", reason: reason)),
                            to: channel.url(prefix + ".json"))
            } catch { statusPublicationFailed = true }
            do {
                let statusBytes = try read(channel.url("capture-status-" + String(statusSequence) + ".json"))
                let contextBytes = (try? read(channel.url(prefix + ".json"))) ?? Data()
                let terminal = ProbePhysicalOperationContextCompletion(schemaVersion: 1, identity: channel.identity,
                    requestSHA256: reply.requestSHA256, replySHA256: replyHash,
                    captureSHA256: ProbePhysicalInputExchange.sha(raw), contextSHA256: ProbePhysicalInputExchange.sha(contextBytes),
                    status: statusBytes, statusSHA256: ProbePhysicalInputExchange.sha(statusBytes), state: "INVALID",
                    deadline: deadline, finishedAt: now())
                try persist(ProbePhysicalOperationChannel.encode(terminal), to: channel.url(prefix + "-result.json"))
            } catch { statusPublicationFailed = true }
        }
    }
}
#endif
