"""Add passive observation and ordered background persistence to copied fixtures."""
import hashlib


STORE='''// Record order is reserved under one lock; all serialization and file work is off-main.
final class ObservationStore: @unchecked Sendable {
    static let shared = ObservationStore()
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "fixture.observation.writer", qos: .utility)
    private var sequence = 0
    private var writeFailed = false
    private var backgroundSequence: Int?
    private let output: URL
    init(output: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("events.jsonl")) {
        self.output = output
        writer.async { FileManager.default.createFile(atPath: output.path, contents: nil) }
    }
    @discardableResult
    func append(_ kind: String, _ payload: [String: Any]) -> Int {
        lock.lock(); defer { lock.unlock() }
        sequence += 1
        let row: [String: Any] = ["sequence": sequence, "run_id": Settings.runID,
            "timestamp": Date().timeIntervalSince1970, "kind": kind, "payload": payload]
        let output = output
        writer.async { [self] in
            guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
                  let handle = try? FileHandle(forWritingTo: output) else { writeFailed = true; return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.write(contentsOf: Data([10]))
            } catch { writeFailed = true; print("Automatic fixture observation write failed") }
        }
        if kind == "native_background" { backgroundSequence = sequence }
        return sequence
    }
    func persistHome(_ idle: Data, request: String, completion: @escaping @Sendable (Data?) -> Void) {
        lock.lock(); let background = backgroundSequence; lock.unlock()
        guard let background = background else { completion(nil); return }
        let destination = output.deletingLastPathComponent().appendingPathComponent("home-input-idle-" + request + ".json")
        // The task was armed before Home. This preserves the existing observation
        // allowance; only the host's finite event inventory can authorize finish.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) { [self] in
            checkpoint("background-" + String(background), sidecar: (destination, idle), completion: completion)
        }
    }
    func checkpoint(_ identifier: String, sidecar: (URL, Data)? = nil, prefix: (Int, String)? = nil,
                    completion: @escaping @Sendable (Data?) -> Void = { _ in }) {
        lock.lock(); defer { lock.unlock() }
        let committed = sequence
        let destination = output.deletingLastPathComponent().appendingPathComponent("events-checkpoint-" + identifier + ".json")
        writer.async { [self] in
            do {
                let bytes = try Data(contentsOf: output)
                guard !writeFailed else { completion(nil); return }
                if let (count, fingerprint) = prefix {
                    guard count > 0, count <= bytes.count, bytes[count - 1] == 10,
                          SHA256.hash(data: bytes.prefix(count)).map({ String(format: "%02x", $0) }).joined() == fingerprint
                    else { completion(nil); return }
                }
                if let (url, data) = sidecar { try data.write(to: url, options: .atomic) }
                let receipt: [String: Any] = ["schema_version": 1, "run_id": Settings.runID,
                    "request_id": identifier, "sequence": committed, "success": !writeFailed,
                    "byte_count": bytes.count, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
                let encoded = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                try encoded.write(to: destination, options: .atomic)
                completion(encoded)
            } catch { writeFailed = true; print("Automatic fixture checkpoint failed"); completion(nil) }
        }
    }
    func event<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        append("rum", row)
    }
}
'''


def render(original, expected_sha256):
    if hashlib.sha256(original).hexdigest()!=expected_sha256:raise ValueError('original automatic observation changed')
    text='import CryptoKit\n'+original.decode();start=text.index('final class ObservationStore:');end=text.index('enum Settings {',start)
    text=text[:start]+STORE+text[end:]
    pairs=[
        ('    static func hit(_ name: String) { ObservationStore.shared.append',
         '    static func hit(_ name: String) { HumanObservation.shared.input(name); ObservationStore.shared.append'),
        ('    static func appeared(_ screen: String) { ObservationStore.shared.append',
         '    static func appeared(_ screen: String) { HumanObservation.shared.appeared(screen); ObservationStore.shared.append'),
        ('        timer = Timer.scheduledTimer',
         '        HumanObservation.shared.start()\n        timer = Timer.scheduledTimer')]
    for before,after in pairs:
        if text.count(before)!=1:raise ValueError('automatic observer anchor changed')
        text=text.replace(before,after)
    return text.encode()
