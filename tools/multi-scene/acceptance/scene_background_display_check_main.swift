// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import Foundation

@main struct BackgroundDisplayChecks {
    struct Case: Decodable {
        let name: String
        let request: Data
        let witness: Data
        let identity: ProbeSceneBackgroundControl.Identity
        let token: String
        let accept: Bool
    }
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { throw ProbeSceneBackgroundDisplayContract.Failure.identity }
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ProbeSceneBackgroundDisplayContract.Failure.sequence
        }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        var results: [[String: Any]] = []
        for item in cases {
            do {
                let result = try ProbeSceneBackgroundDisplayContract.make(request: item.request, witness: item.witness,
                                                                          identity: item.identity, token: item.token)
                try ProbeSceneBackgroundControl.encode(result).write(to: output.appendingPathComponent(item.name + ".json"),
                                                                     options: .withoutOverwriting)
                results.append(["name": item.name, "accepted": true, "pass": item.accept])
            } catch {
                results.append(["name": item.name, "accepted": false, "pass": !item.accept,
                                "errorType": String(describing: type(of: error))])
            }
        }
        let result: [String: Any] = ["state": results.allSatisfy { $0["pass"] as? Bool == true } ? "PASS" : "FAIL",
                                    "controls": results, "nativeRuns": 0, "gatesClosed": []]
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
            .write(to: output.appendingPathComponent("result.json"), options: .withoutOverwriting)
    }
}
