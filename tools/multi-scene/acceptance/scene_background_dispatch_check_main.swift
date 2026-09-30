// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation
import Darwin

@main
struct BackgroundDispatchChecks {
    struct Witness: Decodable {
        let runID: String
        let notificationNames: [String: String]
        let snapshot: ProbePhysicalInputSnapshot
        let interaction: [ProbeSceneBackgroundInteraction]
        var value: ProbeSceneBackgroundWitness {
            .init(runID: runID, notificationNames: notificationNames, snapshot: snapshot, interaction: interaction)
        }
    }
    struct Marker: Decodable {
        let marker: String
        let scene: String
        let nativeSceneID: String
        let before: Witness
        let after: Witness
        var step: ProbeStep { .init(.emitSceneContextMarker, scene: scene, value: marker) }
        var handle: ProbeSceneHandle { .init(logicalSceneID: scene, nativeSceneID: nativeSceneID, disconnectGeneration: 0) }
    }
    struct Control: Decodable {
        let name: String
        let runID: String
        let mode: String
        let arm: Witness
        let markers: [Marker]
        let invocations: Int
        let accepted: Int
        let complete: Bool
        let reason: String?
        let proofs: Int
    }
    struct Result: Encodable {
        let name: String
        let passed: Bool
        let invocations: Int
        let accepted: Int
        let complete: Bool
        let failure: String?
        let latched: Bool
        let ordered: Bool
        let evidence: [ProbeSceneBackgroundDispatch.Evidence]
    }
    enum Invalid: Error { case arguments, controls, mismatch, publication }

    @MainActor
    final class Admission {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }

    @MainActor
    static func exercise(_ control: Control) async -> Result {
        var current = control.arm.value, stopped = false, calls = 0, accepted = 0
        var evidence: [ProbeSceneBackgroundDispatch.Evidence] = []
        var dispatcher: ProbeSceneBackgroundDispatch!
        let executor = ProbeSceneStepExecutor()
        let first = control.markers[0]
        dispatcher = .init(runID: control.runID, observe: { current }, publish: { proof in
            let stage = proof.name.split(separator: ".").dropFirst().first.map(String.init) ?? ""
            if control.mode == "fail-" + stage + "-publication" { throw Invalid.publication }
            evidence.append(proof)
            if proof.name == "h10.before." + first.marker {
                if control.mode == "stop-publication" { stopped = true }
                if control.mode == "reenter-publication" { _ = executor.execute(first.step, background: dispatcher) }
            }
        }, stopped: { stopped })
        if control.mode != "missing-arm" { _ = dispatcher.arm() }
        if control.mode == "repeated-arm" { _ = dispatcher.arm() }

        for (index, marker) in control.markers.enumerated() {
            if dispatcher.failure != nil { break }
            current = marker.before.value
            let handle = control.mode == "wrong-generation"
                ? ProbeSceneHandle(logicalSceneID: marker.scene, nativeSceneID: marker.nativeSceneID, disconnectGeneration: 1)
                : marker.handle
            let action: (ProbeStep) -> ProbeStepExecutionResult = { _ in
                calls += 1
                current = marker.after.value
                if control.mode == "stop-dispatch" { stopped = true }
                if control.mode == "reenter-dispatch" { _ = executor.execute(marker.step, background: dispatcher) }
                return control.mode == "executor-rejected" ? .rejected(reason: "synthetic executor rejection") : .accepted
            }
            executor.configure(handle: handle, execute: action)
            let step = control.mode == "wrong-step" ? ProbeStep(.emitMarker, scene: marker.scene, value: marker.marker) : marker.step
            let outcome: ProbeStepExecutionResult
            if index == 0 && ["suspended", "stop-wait", "cancel-wait", "rebind-wait"].contains(control.mode) {
                // Suspend with valid owners, then change the real injected current
                // observation or stop state before releasing the actual executor.
                current = control.arm.value
                let admission = Admission()
                let task = Task { @MainActor in
                    await admission.wait()
                    return executor.execute(step, background: dispatcher)
                }
                while admission.continuation == nil { await Task.yield() }
                current = marker.before.value
                if control.mode == "stop-wait" { stopped = true }
                if control.mode == "cancel-wait" { task.cancel() }
                if control.mode == "rebind-wait" {
                    executor.configure(handle: .init(logicalSceneID: marker.scene, nativeSceneID: "replaced-native", disconnectGeneration: 0), execute: action)
                }
                admission.release()
                outcome = await task.value
            } else { outcome = executor.execute(step, background: dispatcher) }
            guard outcome == .accepted else { break }
            accepted += 1
            if control.mode == "repeated-marker" {
                _ = executor.execute(step, background: dispatcher)
                break
            }
        }
        let failure = dispatcher.failure
        var latched = true
        if let failure {
            stopped = false
            current = control.arm.value
            let oldCalls = calls
            executor.configure(handle: first.handle) { _ in calls += 1; return .accepted }
            let retry = executor.execute(first.step, background: dispatcher)
            latched = retry == .rejected(reason: failure) && calls == oldCalls && dispatcher.arm() == failure
        }
        let expectedNames = ["h10.arm"] + control.markers.flatMap { marker in
            ["h10.before." + marker.marker, "h10.invoke." + marker.marker, "h10.after." + marker.marker]
        }
        let ordered = !control.complete || (evidence.map(\.name) == expectedNames
            && evidence.allSatisfy { $0.failure == nil }
            && evidence.filter { $0.witness != nil }.count == 11)
        let passed = calls == control.invocations && accepted == control.accepted
            && dispatcher.complete == control.complete && evidence.count == control.proofs && ordered && latched
            && (control.reason.map { failure?.contains($0) == true } ?? (failure == nil))
        return .init(name: control.name, passed: passed, invocations: calls, accepted: accepted,
                     complete: dispatcher.complete, failure: failure, latched: latched, ordered: ordered, evidence: evidence)
    }

    @MainActor
    static func main() async {
        do {
            guard CommandLine.arguments.count == 3 else { throw Invalid.arguments }
            let input = URL(fileURLWithPath: CommandLine.arguments[1])
            let output = URL(fileURLWithPath: CommandLine.arguments[2])
            guard !FileManager.default.fileExists(atPath: output.path) else { throw Invalid.arguments }
            let controls = try JSONDecoder().decode([Control].self, from: Data(contentsOf: input))
            guard !controls.isEmpty, controls.allSatisfy({ $0.markers.count == 5 }),
                  Set(controls.map(\.name)).count == controls.count else { throw Invalid.controls }
            var results: [Result] = []
            for control in controls { results.append(await exercise(control)) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output, options: .withoutOverwriting)
            guard results.allSatisfy(\.passed) else { throw Invalid.mismatch }
            print("PASS \(results.count) synthetic executor controls; no native acceptance")
        } catch { print("FAIL dispatch controls; inspect the preserved result"); exit(1) }
    }
}
