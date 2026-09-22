"""Exercise the exact Swift mapper wrappers and writer on the host, without an app."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def generate():
    source = (HERE / 'ReleaseValidationCapture.swift').read_text()
    mapper = source[source.index('        let view = configuration.viewEventMapper'):source.index('        do {\n            try CoreRegistry')]
    writer = source[source.index('private final class CaptureStore:'):source.index('private struct CaptureFeature:')]
    original = '''directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rum-release-capture-" + (identity["run_id"] ?? "invalid"))'''
    assert writer.count(original) == 1
    writer = writer.replace(original, 'directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAPTURE_TEST_OUTPUT"]!)')
    prelude = '''import Foundation
import CryptoKit
struct Event: Codable, Equatable { var type: String; var value: String }
struct Configuration {
 var viewEventMapper: ((Event) -> Event)?
 var actionEventMapper: ((Event) -> Event?)?
 var resourceEventMapper: ((Event) -> Event?)?
 var errorEventMapper: ((Event) -> Event?)?
 var longTaskEventMapper: ((Event) -> Event?)?
}
final class MapperStore {
 var values: [(Event, String, Bool)] = []
 func mapper(_ event: Event, family: String, accepted: Bool) { values.append((event, family, accepted)) }
}
func wrap(_ configuration: inout Configuration, store: MapperStore) {
'''
    tests = '''
let familyPaths: [(String, WritableKeyPath<Configuration, ((Event) -> Event?)?>)] = [
 ("action", \\.actionEventMapper), ("resource", \\.resourceEventMapper), ("error", \\.errorEventMapper), ("long_task", \\.longTaskEventMapper)]
for (family, path) in familyPaths {
 for behavior in ["absent", "nil", "changed"] {
  var config = Configuration();let store = MapperStore()
  if behavior == "nil" { config[keyPath: path] = { _ in nil } }
  if behavior == "changed" { config[keyPath: path] = { event in Event(type: event.type, value: "changed") } }
  wrap(&config, store: store)
  let event = Event(type: family, value: "original")
  let result = config[keyPath: path]!(event)
  let expected = behavior == "nil" ? nil : Event(type: family, value: behavior == "changed" ? "changed" : "original")
  precondition(result == expected)
  let captured = store.values.last!
  precondition(captured.0 == (expected ?? event) && captured.1 == family && captured.2 == (expected != nil))
 }
}
for change in [false, true] {
 var config = Configuration();let store = MapperStore()
 if change { config.viewEventMapper = { Event(type: $0.type, value: "changed") } }
 wrap(&config, store: store)
 let result = config.viewEventMapper!(Event(type: "view", value: "original"))
 precondition(result.value == (change ? "changed" : "original"))
 precondition(store.values.last!.0 == result && store.values.last!.2)
}
extension CaptureStore { func drainForControl() { writer.sync {} } }
let identity = ["run_id": "10000000-0000-4000-8000-000000000001", "nonce": "20000000-0000-4000-8000-000000000002"]
private let store = CaptureStore(identity: identity)
store.record("configured", fields: ["pid": 1])
let group = DispatchGroup()
for index in 0..<24 {
 DispatchQueue.global().async(group: group) {
  store.record("manual_call", fields: ["operation": "control", "name": String(index)])
 }
}
group.wait()
store.mapper(Event(type: "error", value: "cancelled"), family: "error", accepted: false)
store.checkpoint("30000000-0000-4000-8000-000000000003")
store.drainForControl()
let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAPTURE_TEST_OUTPUT"]!)
let originalCheckpoint = try Data(contentsOf: output.appendingPathComponent("checkpoint-30000000-0000-4000-8000-000000000003.json"))
store.checkpoint("30000000-0000-4000-8000-000000000003")
store.drainForControl()
let duplicateCheckpoint = try Data(contentsOf: output.appendingPathComponent("checkpoint-30000000-0000-4000-8000-000000000003.json"))
precondition(duplicateCheckpoint == originalCheckpoint)
store.checkpoint("40000000-0000-4000-8000-000000000004")
store.drainForControl()
let failed = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("checkpoint-40000000-0000-4000-8000-000000000004.json"))) as! [String: Any]
precondition(failed["success"] as? Bool == false)
print("14 mapper result cases; concurrent writer; immutable duplicate checkpoint; sticky write failure: PASS")
'''
    return prelude + mapper + '\n}\n' + writer + tests


def run(root):
    root = Path(root)
    root.mkdir(exist_ok=False)
    swift = root / 'CaptureControls.swift';swift.write_text(generate())
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode_27.1.app/Contents/Developer',
               CLANG_MODULE_CACHE_PATH=str(root / 'module-cache'), CAPTURE_TEST_OUTPUT=str(root / 'capture'))
    command = ['/Applications/Xcode_27.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', str(swift)]
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
    (root / 'stdout.log').write_bytes(result.stdout);(root / 'stderr.log').write_bytes(result.stderr)
    receipt = dict(schema_version=1, status='PASS' if result.returncode == 0 else 'FAIL', exit_code=result.returncode,
                   source_sha256=hashlib.sha256((HERE / 'ReleaseValidationCapture.swift').read_bytes()).hexdigest(),
                   generated_control_sha256=hashlib.sha256(swift.read_bytes()).hexdigest(),
                   scope='Exact wrapper body and CaptureStore; only filesystem root injected. UIKit and app runtime not executed.',
                   stdout_sha256=hashlib.sha256(result.stdout).hexdigest(), stderr_sha256=hashlib.sha256(result.stderr).hexdigest())
    (root / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))
    if result.returncode:
        print(result.stderr.decode()[:12000])
    return result.returncode


if __name__ == '__main__':
    import sys
    raise SystemExit(run(sys.argv[1]))
