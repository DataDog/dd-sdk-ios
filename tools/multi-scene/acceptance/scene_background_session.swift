// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation

extension ProbeSceneBackgroundWitness: Decodable {
    enum CaptureKeys: String, CodingKey { case schemaVersion, runID, scenarioID, profile, notificationNames, snapshot, interaction }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CaptureKeys.self)
        guard try fields.decode(Int.self, forKey: .schemaVersion) == 1,
              try fields.decode(String.self, forKey: .scenarioID) == "windows.isolated-background-foreground",
              try fields.decode(String.self, forKey: .profile) == "physical-isolated-background-foreground" else {
            throw ProbeSceneBackgroundCapture.Failure.identity
        }
        runID = try fields.decode(String.self, forKey: .runID)
        notificationNames = try fields.decode([String: String].self, forKey: .notificationNames)
        snapshot = try fields.decode(ProbePhysicalInputSnapshot.self, forKey: .snapshot)
        interaction = try fields.decode([ProbeSceneBackgroundInteraction].self, forKey: .interaction)
    }
}

/// App-only composition of native observations, recorder evidence and the host
/// channel. MainActor owns the driver and all native state; waits yield that actor.
@MainActor
private final class ProbeSceneBackgroundSession {
    typealias Control = ProbeSceneBackgroundControl
    typealias Capture = ProbeSceneBackgroundCapture
    let channel: Control
    let capture: Capture
    private let input: ProbePhysicalOperationInput
    private let recorder: ProbeEventRecorder
    private var pump: Task<Void, Never>?
    private var checking = false
    private var nextBoundary = 0
    private var initialOwners: [String: String]?
    private var expectedOwners: [String: String]?
    private(set) var failure: String?
    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    lazy var dispatch = ProbeSceneBackgroundDispatch(runID: channel.identity.runID,
        observe: { [unowned self] in input.snapshotForBackgroundCycle(runID: channel.identity.runID) },
        publish: { [unowned self] evidence in
            let signal = ProbeSignal(kind: .assertion,
                semanticContext: evidence.logicalSceneID.map { .init(logicalSceneID: $0, nativeSceneID: evidence.nativeSceneID) },
                stepKind: evidence.name.hasPrefix("h10.invoke.") ? .emitSceneContextMarker : nil,
                name: evidence.name, result: evidence.failure == nil ? .pass : .inconclusive,
                reason: evidence.witness ?? evidence.failure)
            let recorded = try recorder.h10RecordChecked(signal) { signals in
                if evidence.failure == nil && (evidence.name == "h10.arm" || evidence.name.hasPrefix("h10.before.")) {
                    guard let expectedOwners else { throw Capture.Failure.owner }
                    let snapshot = try Self.encodeSnapshot(signals: signals, terminal: nil)
                    guard try capture.currentOwners(snapshot) == expectedOwners else { throw Capture.Failure.owner }
                }
            }
            try capture.publish(Control.encode(recorded))
        }, stopped: { [unowned self] in failure != nil || channel.admissionFailure(now: Self.now) != nil })

    private lazy var phase: ProbeSceneBackgroundPhase = ProbeSceneBackgroundPhase(control: channel, clock: { Self.now }, observe: { [unowned self] in
        try capture.inspect(boundary: phase.challenge?.name ?? "unbound")
    }, seal: { [unowned self] inspected, proof, display in
        guard dispatch.complete, let challenge = phase.challenge else { throw Capture.Failure.proof }
        return try capture.seal(inspected: inspected, proof: proof, display: display, challenge: challenge) { native in
            let actual = try JSONDecoder().decode(ProbeSceneBackgroundWitness.self, from: native)
            if dispatch.inspectCollection(actual) != nil { throw Capture.Failure.owner }
        }
    })

    var isSealed: Bool { failure == nil && phase.state == .sealed && capture.sealed && dispatch.complete }

    private init(channel: Control, capture: Capture, input: ProbePhysicalOperationInput, recorder: ProbeEventRecorder) {
        self.channel = channel; self.capture = capture; self.input = input; self.recorder = recorder
        pump = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, channel.phase != .closed else { return }
                do { try phase.poll() }
                catch { fail("background channel or evidence publication failed") }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            }
        }
    }

    private static func encodeSnapshot(signals: [ProbeSignal], terminal: ProbeSemanticResult?) throws -> Capture.Snapshot {
        try .init(signals: signals.map { try Control.encode($0) }, terminal: terminal.map { try Control.encode($0) })
    }

    static func make(input: ProbePhysicalOperationInput, recorder: ProbeEventRecorder,
                     oracleSourceSHA256: String) -> ProbeSceneBackgroundSession? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DD_PROBE_BACKGROUND_PROFILE"] == Control.profile,
              environment["DD_PROBE_CAPTURE_JSONL"] == "1",
              environment["MULTISCENE_CODE_IDENTITY_RUN_ID"] == ProbeRuntime.runID,
              let execution = environment["DD_PROBE_BACKGROUND_EXECUTION_DEADLINE_MS"].flatMap(Int64.init),
              let cleanup = environment["DD_PROBE_BACKGROUND_CLEANUP_DEADLINE_MS"].flatMap(Int64.init),
              let revision = environment["MULTISCENE_CODE_IDENTITY_REVISION"],
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        do {
            let url = documents.appendingPathComponent(ProbeRuntime.runID + ".installed-code.json")
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let size = attributes.fileSize, size <= Control.maximumBytes else { return nil }
            let installed = try Data(contentsOf: url)
            guard let code = try JSONSerialization.jsonObject(with: installed) as? [String: Any],
                  code["runID"] as? String == ProbeRuntime.runID, code["sourceRevision"] as? String == revision,
                  code["boundary"] as? String == "before-sdk-initialization",
                  code["processID"] as? Int32 == ProcessInfo.processInfo.processIdentifier else { return nil }
            let identity = Control.Identity(schemaVersion: 1, runID: ProbeRuntime.runID,
                processID: ProcessInfo.processInfo.processIdentifier, scenarioID: Control.scenarioID, profile: Control.profile,
                sourceRevision: revision, installedCodeSHA256: Control.sha(installed), challengeID: UUID().uuidString.lowercased(),
                executionDeadlineMilliseconds: execution, cleanupDeadlineMilliseconds: cleanup)
            var evidence: Capture?
            let channel = try Control(directory: documents.appendingPathComponent(ProbeRuntime.runID + ".background-channel"),
                identity: identity, now: now, observe: { stage in
                    let actual = try ProbeSceneBackgroundIdle.witness(input, stage: stage)
                    if let evidence { _ = try evidence.inspect(boundary: "control-" + stage) }
                    return actual
                }, stop: { ProbeRuntime.scenarioDriver?.stopForCleanup() }, driver: {
                    guard let state = ProbeRuntime.scenarioDriver?.cleanupState else {
                        return .init(requested: false, stopped: false, terminal: nil)
                    }
                    return .init(requested: state.requested, stopped: state.stopped,
                                 terminal: state.terminalBeforeStop.flatMap { try? Control.encode($0) })
                })
            let capture = try Capture(directory: channel.directory.appendingPathComponent("evidence"), identity: identity,
                oracleSourceSHA256: oracleSourceSHA256, snapshot: {
                    let state = recorder.h10Snapshot()
                    return try encodeSnapshot(signals: state.signals, terminal: state.terminal)
                }, witness: { try Control.encode(input.snapshotForBackgroundCycle(runID: identity.runID)) })
            evidence = capture
            return .init(channel: channel, capture: capture, input: input, recorder: recorder)
        } catch { return nil }
    }

    @discardableResult
    private func fail(_ reason: String) -> String {
        if failure == nil {
            failure = reason
            recorder.record(ProbeSignal(kind: .assertion, name: "background-session-failure", result: .inconclusive, reason: reason))
        }
        channel.stopForPhaseFailure(reason)
        return failure ?? reason
    }

    private func live() throws {
        guard failure == nil, !Task.isCancelled, channel.admissionFailure(now: Self.now) == nil else {
            throw Capture.Failure.identity
        }
    }

    private func wait() async throws {
        try live()
        try await Task.sleep(nanoseconds: 100_000_000)
        try live()
    }

    private func barrier(_ index: Int) async throws {
        try phase.begin(index)
        while phase.state == .waiting { try await wait() }
        try live()
        guard phase.state == .granted, let raw = phase.inspectedObservation else { throw Capture.Failure.proof }
        let (_, inspected) = try capture.capture(raw)
        let selected = try capture.currentOwners(inspected.snapshot)
        switch index {
        case 0:
            guard Set(selected.keys) == ["scene-A", "scene-B"], Set(selected.values).count == 2 else { throw Capture.Failure.owner }
            initialOwners = selected
        case 1:
            guard let b = initialOwners?["scene-B"], selected == ["scene-B": b] else { throw Capture.Failure.owner }
        case 2:
            guard let initialOwners, Set(selected.keys) == ["scene-A", "scene-B"],
                  selected["scene-B"] == initialOwners["scene-B"], selected["scene-A"] != initialOwners["scene-A"],
                  Set(selected.values).count == 2 else { throw Capture.Failure.owner }
        default: throw Capture.Failure.proof
        }
        // Permission never replaces the current mapper prefix at the execution boundary.
        let current = recorder.h10Snapshot()
        guard current.terminal == nil,
              try capture.currentOwners(Self.encodeSnapshot(signals: current.signals, terminal: nil)) == selected else {
            throw Capture.Failure.owner
        }
        try phase.consume(index)
        expectedOwners = selected
        if index == 0, dispatch.arm() != nil { throw Capture.Failure.owner }
    }

    func admission(index: Int, step: ProbeStep, after: Bool) async -> String? {
        guard !checking, nextBoundary == index * 2 + (after ? 1 : 0), (0...6).contains(index) else {
            return fail("background driver admission order differs")
        }
        checking = true
        defer { checking = false }
        do {
            if index == 0 && !after {
                while channel.phase == .waiting && !Task.isCancelled && Self.now < channel.identity.executionDeadlineMilliseconds {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            try live()
            if !after, let phaseIndex = [2: 0, 4: 1, 5: 2][index] { try await barrier(phaseIndex) }
            if index == 6 && after {
                guard dispatch.complete, let invocation = recorder.snapshot().last(where: {
                    $0.name == "h10.invoke.B.after-A-foreground" && $0.result == .pass
                }) else { throw Capture.Failure.work }
                try phase.beginCollection(finalInvocationSequence: invocation.sequence)
                while phase.state == .waiting { try await wait() }
                try live()
                guard isSealed else { throw Capture.Failure.proof }
            }
            nextBoundary += 1
            return nil
        } catch { return fail("background ownership, capture or phase admission failed") }
    }
}
