"""Add passive observation and ordered background persistence to copied fixtures."""
import hashlib


STORE='''// Record order is reserved under one lock; all serialization and file work is off-main.
final class ObservationStore: @unchecked Sendable {
    static let shared = ObservationStore()
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "fixture.observation.writer", qos: .utility)
    private var sequence = 0
    private var writeFailed = false
    private let output: URL
    init() {
        output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("events.jsonl")
        let output = output
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
        if kind == "native_background" {
            let identifier = "background-" + String(sequence)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) { [self] in checkpoint(identifier) }
        }
        return sequence
    }
    func checkpoint(_ identifier: String) {
        lock.lock(); defer { lock.unlock() }
        let committed = sequence
        let destination = output.deletingLastPathComponent().appendingPathComponent("events-checkpoint-" + identifier + ".json")
        writer.async { [self] in
            do {
                let bytes = try Data(contentsOf: output)
                let receipt: [String: Any] = ["schema_version": 1, "run_id": Settings.runID,
                    "request_id": identifier, "sequence": committed, "success": !writeFailed,
                    "byte_count": bytes.count, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
                try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: destination, options: .atomic)
            } catch { writeFailed = true; print("Automatic fixture checkpoint failed") }
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
