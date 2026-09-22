import Foundation

@main struct EvidenceControls {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let output = root.appendingPathComponent("evidence.json")
        let writer = S2WebViewEvidence(identity: ["run_id": "controlled"], output: output)
        DispatchQueue.concurrentPerform(iterations: 100) { writer.record("concurrent", fields: ["index": $0]) }
        let cutoff = try writer.close(state: "PASS")
        try await writer.flush()
        let initial = try Data(contentsOf: output)
        let document = try JSONSerialization.jsonObject(with: initial) as! [String: Any]
        let rows = document["records"] as! [[String: Any]]
        precondition(cutoff == 101 && document["durable_sequence"] as? Int == 101 && document["closed_sequence"] as? Int == 101)
        precondition(rows.enumerated().allSatisfy { $0.element["sequence"] as? Int == $0.offset + 1 })
        do { _ = try writer.close(state: "PASS"); fatalError("cutoff reused") } catch S2WebViewEvidence.Failure.closed { }
        writer.record("late-mapper")
        try await writer.flush()
        let final = try Data(contentsOf: output)
        let changed = try JSONSerialization.jsonObject(with: final) as! [String: Any]
        precondition(final != initial && changed["closed_sequence"] as? Int == 101 && changed["durable_sequence"] as? Int == 102)
        precondition((changed["records"] as! [[String: Any]]).last?["after_cutoff"] as? Bool == true)
        let failing = S2WebViewEvidence(identity: [:], output: root.appendingPathComponent("missing/evidence.json"))
        failing.record("cannot-persist")
        do { try await failing.flush(); fatalError("failure hidden") } catch S2WebViewEvidence.Failure.persistence { }
        failing.record("still-failed")
        do { try await failing.flush(); fatalError("sticky failure lost") } catch S2WebViewEvidence.Failure.persistence { }
        print("PASS: concurrent ordering, durable seal, duplicate seal, post-cutoff retention, sticky persistence")
    }
}
