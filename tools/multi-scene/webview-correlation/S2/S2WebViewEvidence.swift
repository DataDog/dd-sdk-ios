import Foundation

/// Synthetic fixture evidence; callbacks retain scalar values, never UI objects.
final class S2WebViewEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "com.datadoghq.s2.webview-evidence")
    private let identity: [String: String]
    private let output: URL
    private var records: [[String: Any]] = []
    private var persistenceFailure = false

    init(identity: [String: String], output: URL) {
        self.identity = identity
        self.output = output
    }

    @discardableResult
    func record(_ kind: String, fields: [String: Any] = [:]) -> Int {
        lock.lock(); defer { lock.unlock() }
        return append(kind, fields: fields, wall: Int64(Date().timeIntervalSince1970 * 1_000))
    }

    /// Generate the immutable payload with the exact wall timestamp of its receipt.
    func freeze(marker: String, service: String, documentID: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let wall = Int64(Date().timeIntervalSince1970 * 1_000)
        let event: [String: Any] = [
            "type": "view", "date": wall, "source": "browser", "service": service,
            "application": ["id": "browser-application"],
            "session": ["id": "browser-session", "type": "user", "has_replay": true],
            "view": [
                "id": UUID().uuidString.lowercased(), "name": marker,
                "url": "https://s2-webview.invalid/\(documentID)/\(marker)",
                "is_active": false, "time_spent": 1_000_000, "loading_type": "initial_load",
                "action": ["count": 0], "resource": ["count": 0],
                "error": ["count": 0], "long_task": ["count": 0]
            ],
            "_dd": ["format_version": 2, "document_version": 1],
            "context": ["probe": ["run_id": identity["run_id"] ?? "", "marker": marker]]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["eventType": "view", "event": event], options: [.sortedKeys])
        guard let body = String(data: data, encoding: .utf8) else { throw Failure.encoding }
        append("envelope-frozen", fields: ["marker": marker, "body_json": body], wall: wall)
        return body
    }

    /// SDK and WebKit callbacks only enqueue immutable scalar snapshots.
    /// The scenario must await this barrier before publishing its terminal receipt.
    func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.async {
                self.lock.lock()
                let failed = self.persistenceFailure
                self.lock.unlock()
                if failed { continuation.resume(throwing: Failure.persistence) }
                else { continuation.resume() }
            }
        }
    }

    func matching(_ kind: String, field: String? = nil, value: String? = nil) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return records.filter { row in
            guard row["kind"] as? String == kind else { return false }
            guard let field else { return true }
            return row[field] as? String == value
        }
    }

    private func append(_ kind: String, fields: [String: Any], wall: Int64) -> Int {
        var row = fields
        let sequence = records.count + 1
        row["kind"] = kind
        row["sequence"] = sequence
        row["wall_ms"] = wall
        row["monotonic_ns"] = DispatchTime.now().uptimeNanoseconds
        records.append(row)
        let snapshot = records
        // Enqueue under the same lock so concurrent mapper and WebKit calls retain order.
        writer.async { self.persist(snapshot) }
        return sequence
    }

    private func persist(_ snapshot: [[String: Any]]) {
        lock.lock()
        let failed = persistenceFailure
        lock.unlock()
        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "schema_version": 1, "identity": identity, "records": snapshot,
                "durable_sequence": snapshot.count, "persistence_failure": failed
            ], options: [.sortedKeys])
            try data.write(to: output, options: .atomic)
        } catch {
            lock.lock(); persistenceFailure = true; lock.unlock()
        }
    }

    enum Failure: Error { case encoding, persistence }
}
