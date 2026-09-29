/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// App-only adapter. The driver, UIKit observer and transport pump share MainActor.
@MainActor
private final class ProbeFocusSession {
    let channel: ProbeFocusControl
    private var pump: Task<Void, Never>?

    private init(channel: ProbeFocusControl) {
        self.channel = channel
        pump = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.channel.phase != .closed else { return }
                // A failed publication seals work; a later stop can still prove cleanup.
                do { try self.channel.poll(now: Self.now) } catch { }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            }
        }
    }
    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    static func make(input: ProbePhysicalOperationInput) -> ProbeFocusSession? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DD_PROBE_FOCUS_ACTIVATION_PROFILE"] == ProbeFocusControl.profile,
              environment["DD_PROBE_CAPTURE_JSONL"] == "1",
              let execution = environment["DD_PROBE_FOCUS_EXECUTION_DEADLINE_MS"].flatMap(Int64.init),
              let cleanup = environment["DD_PROBE_FOCUS_CLEANUP_DEADLINE_MS"].flatMap(Int64.init),
              let revision = environment["MULTISCENE_CODE_IDENTITY_REVISION"],
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        do {
            let url = documents.appendingPathComponent(ProbeRuntime.runID + ".installed-code.json")
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let size = attributes.fileSize, size <= ProbeFocusControl.maximumBytes else { return nil }
            let installed = try Data(contentsOf: url)
            guard let code = try JSONSerialization.jsonObject(with: installed) as? [String: Any],
                  code["runID"] as? String == ProbeRuntime.runID,
                  code["sourceRevision"] as? String == revision,
                  code["boundary"] as? String == "before-sdk-initialization",
                  code["processID"] as? Int32 == ProcessInfo.processInfo.processIdentifier else { return nil }
            let identity = ProbeFocusControl.Identity(schemaVersion: 1, runID: ProbeRuntime.runID,
                processID: ProcessInfo.processInfo.processIdentifier, scenarioID: ProbeFocusControl.scenarioID,
                profile: ProbeFocusControl.profile, sourceRevision: revision,
                installedCodeSHA256: ProbeFocusControl.sha(installed), challengeID: UUID().uuidString.lowercased(),
                executionDeadlineMilliseconds: execution, cleanupDeadlineMilliseconds: cleanup)
            let channel = try ProbeFocusControl(directory: documents.appendingPathComponent(ProbeRuntime.runID + ".focus-channel"),
                identity: identity, now: now, observe: { stage in try witness(input, stage: stage) },
                stop: { ProbeRuntime.scenarioDriver?.stopForCleanup() }, driver: {
                    guard let state = ProbeRuntime.scenarioDriver?.cleanupState else {
                        return .init(requested: false, stopped: false, terminal: nil)
                    }
                    return .init(requested: state.requested, stopped: state.stopped,
                                 terminal: state.terminalBeforeStop.flatMap { try? ProbeFocusControl.encode($0) })
                })
            return .init(channel: channel)
        } catch { return nil }
    }

    func admission(index: Int, after: Bool) async -> String? {
        if index == 0 && !after {
            while channel.phase == .waiting && !Task.isCancelled {
                if Self.now >= channel.identity.executionDeadlineMilliseconds { break }
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return "focus admission cancelled" }
            }
        }
        guard !Task.isCancelled else { return "focus admission cancelled" }
        return channel.admissionFailure(now: Self.now)
    }

    /// Background peers cannot receive user input, and need not remain mounted or key.
    /// Every connected fixture owner still needs its original reliable touch observer.
    static func idleFailure(_ value: ProbePhysicalInputSnapshot, stage: String) -> String? {
        if let reason = value.failure ?? value.continuity?.failure { return reason }
        let labels = value.scenes.map(\.logicalSceneID)
        guard stage == "arm" || stage == "stop", value.applicationActive,
              labels == ["scene-A"] || (stage == "stop" && labels == ["scene-A", "scene-B"]),
              let continuity = value.continuity, continuity.owners.map(\.logicalSceneID) == labels,
              value.input.map(\.logicalSceneID) == labels,
              Set(continuity.owners.map(\.nativeSceneID)).count == labels.count,
              Set(continuity.owners.map(\.windowIdentity)).count == labels.count,
              Set(continuity.owners.map(\.rootIdentity)).count == labels.count,
              Set(value.input.map(\.observerIdentity)).count == labels.count,
              value.connectedSceneIDs == continuity.owners.map(\.nativeSceneID).sorted(),
              value.inventory.map(\.nativeSceneID).sorted() == value.connectedSceneIDs,
              value.scenes.contains(where: { $0.activationState == "foreground-active" })
        else { return "focus idle requires the complete active fixture owner inventory" }
        for owner in continuity.owners {
            guard let scene = value.scenes.first(where: { $0.logicalSceneID == owner.logicalSceneID }),
                  let input = value.input.first(where: { $0.logicalSceneID == owner.logicalSceneID }),
                  let inventory = value.inventory.first(where: { $0.nativeSceneID == owner.nativeSceneID }),
                  scene.nativeSceneID == owner.nativeSceneID, scene.generation == owner.generation,
                  scene.windowIdentity == owner.windowIdentity, scene.rootIdentity == owner.rootIdentity,
                  input.nativeSceneID == owner.nativeSceneID, input.generation == owner.generation,
                  input.windowIdentity == owner.windowIdentity, input.rootIdentity == owner.rootIdentity,
                  !input.observerIdentity.isEmpty, scene.connected, input.attached, input.enabled, input.reliable,
                  input.touches == 0, !input.transitioning, !input.resizing,
                  ["foreground-active", "foreground-inactive", "background"].contains(scene.activationState),
                  inventory.activationState == scene.activationState else { return "focus input is active, detached or replaced" }
            let windows = inventory.windows.filter { $0.fixtureOwner == owner.logicalSceneID }
            guard windows.count == 1, let window = windows.first,
                  window.identity == owner.windowIdentity, window.rootIdentity == owner.rootIdentity, window.sceneMatches,
                  inventory.windows.filter({ $0.identity == owner.windowIdentity }).count == 1,
                  inventory.windows.filter({ $0.key }).map(\.identity) == (inventory.keyWindowIdentity.map({ [$0] }) ?? [])
            else { return "focus owned window or key-window inventory differs" }
            if scene.activationState != "background" {
                guard input.mounted, window.mounted, !window.hidden, window.alpha.isFinite, window.alpha > 0
                else { return "focus foreground owner is not visible and mounted" }
            }
            if scene.activationState == "foreground-active" && inventory.keyWindowIdentity != owner.windowIdentity {
                return "focus active owner is not the key window"
            }
        }
        return nil
    }

    static func witness(_ input: ProbePhysicalOperationInput, stage: String) throws -> ProbeFocusControl.Observation {
        let before = input.snapshot(), after = input.snapshot()
        let beforeBytes = try ProbeFocusControl.encode(before), afterBytes = try ProbeFocusControl.encode(after)
        var reason = idleFailure(before, stage: stage) ?? idleFailure(after, stage: stage)
        // Preserve geometry verbatim but compare ownership and activity, not floating-point spelling.
        if reason == nil && (before.input != after.input || before.continuity != after.continuity
            || before.applicationActive != after.applicationActive || before.connectedSceneIDs != after.connectedSceneIDs
            || activity(before) != activity(after)) { reason = "focus owner or input changed across idle capture" }
        return .init(before: beforeBytes, after: afterBytes, idle: reason == nil, reason: reason)
    }

    private static func activity(_ value: ProbePhysicalInputSnapshot) -> [String] {
        value.inventory.flatMap { scene in
            [scene.nativeSceneID, scene.activationState, scene.keyWindowIdentity ?? ""] + scene.windows.flatMap { window in
                [window.identity, window.rootIdentity ?? "", window.fixtureOwner ?? "", String(window.sceneMatches),
                 String(window.key), String(window.hidden), String(window.mounted)]
            }
        }
    }
}
