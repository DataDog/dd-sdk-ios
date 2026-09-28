"""Execute the exact fixture writer on macOS without UIKit or a simulator."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import human_variant


@unittest.skipUnless(sys.platform=='darwin','requires the local Apple Swift toolchain')
class NativeWriter(unittest.TestCase):
    def test_serial_home_barriers_and_failures(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);source=root/'Writer.swift';binary=root/'writer'
            source.write_text('import Foundation\nimport CryptoKit\nenum Settings { static let runID = "writer-control" }\n'+human_variant.STORE+r'''
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func wait(_ start: (@escaping @Sendable (Data?) -> Void) -> Void) -> Data? {
    final class Result: @unchecked Sendable { var value: Data? }
    let result = Result(), signal = DispatchSemaphore(value: 0)
    start { result.value = $0; signal.signal() }
    precondition(signal.wait(timeout: .now() + 10) == .success, "writer did not complete")
    return result.value
}
func hash(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
let output = root.appendingPathComponent("events.jsonl")
let store = ObservationStore(output: output)
precondition(wait { store.persistHome(Data(), request: "unarmed", completion: $0) } == nil)
DispatchQueue.concurrentPerform(iterations: 32) { store.append("concurrent", ["value": $0]) }
let home = store.append("native_background", [:])
store.append("geometry", [:])
let idle = Data("idle-sidecar".utf8)
let checkpoint = wait { store.persistHome(idle, request: "home", completion: $0) }!
let first = try Data(contentsOf: output)
let receipt = try JSONSerialization.jsonObject(with: checkpoint) as! [String: Any]
let rows = try first.split(separator: 10).map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
precondition(rows.map { $0["sequence"] as! Int } == Array(1...34))
precondition(receipt["sequence"] as! Int == 34 && receipt["byte_count"] as! Int == first.count)
precondition(receipt["sha256"] as! String == hash(first))
let savedIdle = try Data(contentsOf: root.appendingPathComponent("home-input-idle-home.json"))
let savedCheckpoint = try Data(contentsOf: root.appendingPathComponent("events-checkpoint-background-" + String(home) + ".json"))
precondition(savedIdle == idle && savedCheckpoint == checkpoint)
store.append("rum", ["delayed": true])
let final = wait { store.checkpoint("finish", prefix: (first.count, hash(first)), completion: $0) }!
let finalReceipt = try JSONSerialization.jsonObject(with: final) as! [String: Any]
precondition(finalReceipt["sequence"] as! Int == 35)
let after = try Data(contentsOf: output)
precondition(after.starts(with: first) && finalReceipt["sha256"] as! String == hash(after))
precondition(wait { store.checkpoint("wrong", prefix: (first.count, String(repeating: "0", count: 64)), completion: $0) } == nil)
precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("events-checkpoint-wrong.json").path))
let missing = root.appendingPathComponent("missing/idle.json")
precondition(wait { store.checkpoint("sidecar-failure", sidecar: (missing, idle), completion: $0) } == nil)
precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("events-checkpoint-sidecar-failure.json").path))
precondition(wait { store.checkpoint("after-failure", completion: $0) } == nil)
print("WRITER_ORDERING_PREFIX_AND_FAILURE_CONTROLS_PASS")
''')
            compile=subprocess.run(['xcrun','swiftc','-swift-version','5',str(source),'-o',str(binary)],
                text=True,capture_output=True,timeout=90,env=dict(os.environ))
            self.assertEqual(compile.returncode,0,compile.stderr)
            run=subprocess.run([str(binary),str(root)],text=True,capture_output=True,timeout=30)
            self.assertEqual(run.returncode,0,run.stderr)
            self.assertIn('WRITER_ORDERING_PREFIX_AND_FAILURE_CONTROLS_PASS',run.stdout)

if __name__=='__main__':unittest.main()
