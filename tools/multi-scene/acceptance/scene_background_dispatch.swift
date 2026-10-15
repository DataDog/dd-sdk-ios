// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation

/// Isolated fixture wrapper. All callbacks and the actual executor are synchronous
/// on MainActor; asynchronous host permission must finish before entering here.
@MainActor
internal final class ProbeSceneBackgroundDispatch {
    static let scenarioID = "windows.isolated-background-foreground"

    struct Evidence: Encodable {
        let name: String
        let logicalSceneID: String?
        let nativeSceneID: String?
        let witness: String?
        let failure: String?
    }

    private let guardrail: ProbeSceneBackgroundGuard
    private let observe: () -> ProbeSceneBackgroundWitness
    private let publish: (Evidence) throws -> Void
    private let stopped: () -> Bool
    private var busy = false
    private(set) var failure: String?

    init(runID: String, observe: @escaping () -> ProbeSceneBackgroundWitness,
         publish: @escaping (Evidence) throws -> Void, stopped: @escaping () -> Bool) {
        guardrail = .init(runID: runID)
        self.observe = observe
        self.publish = publish
        self.stopped = stopped
    }

    var complete: Bool { failure == nil && guardrail.complete }

    func inspectCollection(_ value: ProbeSceneBackgroundWitness) -> String? {
        if let reason = interruption() { return reason }
        guard !busy else { return reject("background collection reentered dispatch") }
        if let reason = guardrail.inspectCollection(value) { return reject(reason) }
        return nil
    }

    private func reject(_ reason: String) -> String {
        failure = failure ?? reason
        return failure ?? reason
    }

    private func interruption() -> String? {
        if let failure { return failure }
        if Task.isCancelled || stopped() { return reject("background dispatch stopped or cancelled") }
        return nil
    }

    private func record(_ name: String, witness: ProbeSceneBackgroundWitness? = nil,
                        scene: String? = nil, native: String? = nil, reason: String? = nil) {
        do {
            let json = try witness.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
            try publish(.init(name: name, logicalSceneID: scene, nativeSceneID: native,
                              witness: json, failure: reason))
        } catch { _ = reject("background evidence publication failed") }
    }

    /// The host separately proves current mapper owners and display before arming.
    func arm() -> String? {
        if let reason = interruption() { return reason }
        guard !busy else { return reject("background dispatch reentered") }
        busy = true
        defer { busy = false }
        let value = observe()
        let reason = guardrail.arm(value)
        if let reason { _ = reject(reason) }
        record("h10.arm", witness: value, reason: reason)
        return interruption()
    }

    func execute(_ step: ProbeStep, handle: ProbeSceneHandle,
                 dispatch: () -> ProbeStepExecutionResult) -> ProbeStepExecutionResult {
        if let reason = interruption() { return .rejected(reason: reason) }
        guard !busy else { return .rejected(reason: reject("background dispatch reentered")) }
        busy = true
        defer { busy = false }
        guard step.kind == .emitSceneContextMarker, let marker = step.value,
              let scene = step.scene, scene == handle.logicalSceneID else {
            return .rejected(reason: reject("background dispatch has the wrong step or executor"))
        }
        let before = observe()
        let owner = before.snapshot.continuity?.owners.first { $0.logicalSceneID == scene }
        let reason: String?
        if owner?.nativeSceneID != handle.nativeSceneID || owner?.generation != handle.disconnectGeneration {
            reason = reject("background executor no longer has its observed native owner")
        } else {
            reason = guardrail.before(before, marker: marker, scene: scene, nativeSceneID: handle.nativeSceneID)
            if let reason { _ = reject(reason) }
        }
        record("h10.before." + marker, witness: before, scene: scene, native: handle.nativeSceneID, reason: reason)
        if let reason = interruption() { return .rejected(reason: reason) }

        let result = dispatch()
        // Capture the real post-dispatch state before any receipt publication.
        let after = observe()
        if case .rejected(let reason) = result { _ = reject("scene executor rejected marker: " + reason) }
        _ = interruption()
        if failure == nil, let reason = guardrail.invoked(marker: marker, scene: scene, nativeSceneID: handle.nativeSceneID) {
            _ = reject(reason)
        }
        let invocationFailure = failure
        if failure == nil, let reason = guardrail.after(after, marker: marker, scene: scene, nativeSceneID: handle.nativeSceneID) {
            _ = reject(reason)
        }
        record("h10.invoke." + marker, scene: scene, native: handle.nativeSceneID, reason: invocationFailure)
        record("h10.after." + marker, witness: after, scene: scene, native: handle.nativeSceneID, reason: failure)
        if let reason = interruption() { return .rejected(reason: reason) }
        return .accepted
    }
}
