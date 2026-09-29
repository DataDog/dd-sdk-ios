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

internal struct ProbePhysicalInputSnapshot: Codable, Equatable {
    let scenes: [ProbePhysicalSceneObservation]
    let input: [ProbePhysicalInputWindow]
    let connectedSceneIDs: [String]
    let applicationActive: Bool
    let inventory: [ProbePhysicalSceneInventory]
    let failure: String?

    @MainActor
    func idleFailure() -> String? {
        if let failure { return failure }
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
    private(set) var failure: String?
    init(registry: ProbeSceneRegistry) { self.registry = registry }

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
        }
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
                     applicationActive: UIApplication.shared.applicationState == .active, inventory: inventory, failure: failure)
    }
}

internal struct ProbePhysicalInputRequest: Codable, Equatable {
    let runID: String
    let processID: Int32
    let profile: ProbePhysicalOperationProfile
    let phase: String
    let nonce: String
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
    private var consumedNonces = Set<String>()
    private var pendingSetup: (String, ProbePhysicalInputCapture)?
    private var admitted = false

    init(runID: String, processID: Int32, profile: ProbePhysicalOperationProfile) {
        self.runID = runID; self.processID = processID; self.profile = profile
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
              Set(object.keys) == ["runID", "processID", "profile", "phase", "nonce"],
              let nested = object["profile"] as? [String: Any],
              Set(nested.keys) == ["sourceRevision", "buildConfiguration", "scenarioSHA256", "inference"] else { throw Rejection.request }
        let request = try JSONDecoder().decode(ProbePhysicalInputRequest.self, from: raw)
        guard request.runID == runID, request.processID == processID, request.profile == profile,
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
    enum Failure: Error { case identity, file, message, reused, invalidated }
    let identity: ProbePhysicalOperationChannelIdentity
    private let directory: URL
    private let exchange: ProbePhysicalInputExchange
    private let observe: () -> ProbePhysicalInputSnapshot
    private var lastPublication: String?
    private var consumedPublications = Set<String>()
    private var consumedCommands = Set<String>()
    private(set) var failure: String?
    private let publish: (Data, URL) throws -> Void
    static let maximumBytes = 65_536

    init(runID: String, processID: Int32, profile: ProbePhysicalOperationProfile,
         installedCode: Data, directory: URL, observe: @escaping () -> ProbePhysicalInputSnapshot,
         publish: ((Data, URL) throws -> Void)? = nil) throws {
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
        self.identity = .init(schemaVersion: 1, runID: runID, processID: processID, profile: profile,
                              challengeID: UUID().uuidString, installedCodeSHA256: ProbePhysicalInputExchange.sha(installedCode),
                              executionArmed: false)
        self.directory = directory
        self.exchange = .init(runID: runID, processID: processID, profile: profile)
        self.observe = observe
        self.publish = publish ?? Self.writeNew
        try self.publish(Self.encode(identity), url("challenge.json"))
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
            guard try Self.encode(message) == bytes, message.schemaVersion == 1,
                  message.runID == identity.runID, message.processID == identity.processID,
                  message.challengeID == identity.challengeID, UUID(uuidString: message.commandID) != nil else {
                throw Failure.message
            }
            commandID = message.commandID
            guard consumedCommands.insert(message.commandID).inserted else { throw Failure.reused }
            let request = try JSONDecoder().decode(ProbePhysicalInputRequest.self, from: message.inputRequest)
            guard try Self.encode(request) == message.inputRequest else { throw Failure.message }
            guard failure == nil || request.phase == "cleanup" else { throw Failure.invalidated }
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
