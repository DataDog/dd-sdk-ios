// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation
import Darwin

/// Portable synthetic controls, not a device or SDK workload.
@main
struct BackgroundGuardChecks {
    struct Witness: Decodable {
        let runID: String
        let notificationNames: [String: String]
        let snapshot: ProbePhysicalInputSnapshot
        let interaction: [ProbeSceneBackgroundInteraction]
        var value: ProbeSceneBackgroundWitness {
            .init(runID: runID, notificationNames: notificationNames, snapshot: snapshot, interaction: interaction)
        }
    }
    struct Step: Decodable {
        let operation: String
        let marker: String?
        let scene: String?
        let nativeSceneID: String?
        let witness: Witness?
    }
    struct Control: Decodable {
        let name: String
        let runID: String
        let steps: [Step]
        let firstFailure: Int?
        let acceptedMarkers: Int
        let completed: Bool
    }
    struct Result: Encodable {
        let name: String
        let passed: Bool
        let observedFirstFailure: Int?
        let acceptedMarkers: Int
        let completed: Bool
        let failureLatched: Bool
    }
    enum Invalid: Error { case arguments, control, mismatch }

    @MainActor
    static func main() {
        do { try run() }
        catch { print("FAIL synthetic guard control execution; inspect the preserved result"); exit(1) }
    }

    @MainActor
    static func run() throws {
        guard CommandLine.arguments.count == 3 else { throw Invalid.arguments }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Invalid.arguments }
        let controls = try JSONDecoder().decode([Control].self, from: Data(contentsOf: input))
        guard !controls.isEmpty, Set(controls.map(\.name)).count == controls.count else { throw Invalid.control }
        var results: [Result] = []
        for control in controls {
            let guardrail = ProbeSceneBackgroundGuard(runID: control.runID)
            var firstFailure: Int?, originalReason: String?, approved = 0, latched = true
            for (index, step) in control.steps.enumerated() {
                let reason: String?
                if step.operation == "arm", let witness = step.witness {
                    reason = guardrail.arm(witness.value)
                } else if let marker = step.marker, let scene = step.scene, let native = step.nativeSceneID {
                    switch step.operation {
                    case "before":
                        guard let witness = step.witness else { throw Invalid.control }
                        reason = guardrail.before(witness.value, marker: marker, scene: scene, nativeSceneID: native)
                        if reason == nil { approved += 1 }
                    case "invoked": reason = guardrail.invoked(marker: marker, scene: scene, nativeSceneID: native)
                    case "after":
                        guard let witness = step.witness else { throw Invalid.control }
                        reason = guardrail.after(witness.value, marker: marker, scene: scene, nativeSceneID: native)
                    default: throw Invalid.control
                    }
                } else { throw Invalid.control }
                if let originalReason { latched = latched && reason == originalReason }
                else if let reason { firstFailure = index; originalReason = reason }
            }
            let passed = firstFailure == control.firstFailure && approved == control.acceptedMarkers
                && guardrail.complete == control.completed && latched
            results.append(.init(name: control.name, passed: passed, observedFirstFailure: firstFailure,
                                 acceptedMarkers: approved, completed: guardrail.complete, failureLatched: latched))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: output, options: .withoutOverwriting)
        guard results.allSatisfy(\.passed) else { throw Invalid.mismatch }
        print("PASS \(results.count) synthetic Swift guard controls; no native acceptance")
    }
}
