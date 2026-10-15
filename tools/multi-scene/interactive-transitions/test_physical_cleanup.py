"""Cleanup must not replace a process, invent release, or overwrite stopped evidence."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import physical_capture
import physical_cleanup as cleanup
import physical_release as release
from acceptance_common import Rejected
from capture_io import encoded
from test_physical import response
from test_physical_release import BINDING, IDENTITY


class Cleanup(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.clock = 100.0
        self.addCleanup(patch.stopall)
        patch.object(cleanup.time, "time", side_effect=lambda: self.clock).start()
        self.path = "file:///private/owned/UIKitTransitions.app/UIKitTransitions"
        self.operations = []
        self.rows = [dict(sequence=1, run_id="run", kind="launch", payload=copy.deepcopy(IDENTITY)),
                     dict(sequence=2, run_id="run", kind="human_failure", payload=dict(reason="retained")),
                     dict(sequence=3, run_id="run", kind="geometry", payload=dict(
                         scenes=[dict(id="scene", activation=2)]))]
        self.data = b"".join(encoded(r) for r in self.rows)
        self.before = self.data
        self.snapshot = None
        self.checkpoint = None
        self.process = dict(processIdentifier=12, executable=self.path)
        self.activation = response("devicectl.device.process.launch", result=dict(
            deviceIdentifier="device", process=copy.deepcopy(self.process),
            launchOptions=dict(activatedWhenStarted=True, terminateExistingInstances=False)))
        self.remote = SimpleNamespace(processes=self.processes, command=self.command, push=self.push)
        self.collector = SimpleNamespace(remote=self.remote, device="device", run="run", pid=12,
            process_path=self.path, framework="UIKit", bundle="bundle", download=self.download,
            binding=copy.deepcopy(BINDING))
        request = dict(kind="HUMAN_RELEASE_REQUIRED", request_id="release-request", run_id="run",
                       issued_at=90, deadline=120)
        (self.folder / "request.json").write_bytes(encoded(request))
        release.acknowledge(self.folder / "request.json", "Released")
        self.summary = self.folder / "original-summary.json"
        self.summary.write_bytes(b'{"state":"INVALID","cleanup":"INVALID"}\n')
        self.original_summary = self.summary.read_bytes()

    def processes(self, label, deadline):
        self.operations.append(label)
        return [copy.deepcopy(self.process)]

    def command(self, argv, label, deadline):
        self.assertEqual(argv, ["device", "process", "launch", "--activate", "bundle"])
        self.assertEqual((self.folder / "before-reactivation.jsonl").read_bytes(), self.before)
        self.assertTrue((self.folder / "operator-released.json").exists())
        self.operations.append(label)
        return self.activation, dict(returncode=0)

    def push(self, bundle, source, destination, label, deadline):
        self.operations.append(label)
        if label == "cleanup-idle-payload":
            self.snapshot = source.read_bytes()
        elif label == "cleanup-idle-publish":
            request = json.loads(self.snapshot)
            idle = dict(sequence=len(self.rows) + 1, run_id="run", kind="human_snapshot", payload=dict(
                request_id=request["request_id"], request_sha256=hashlib.sha256(self.snapshot).hexdigest(),
                phase="cleanup.idle", input_state=dict(valid=True, **BINDING,
                    pans=[dict(id="pan", state=0, touches=0)], coordinators=[]),
                topology=dict(**{"bound_" + k: v for k, v in BINDING.items()},
                              window_alive=True, root_alive=True, bound_root_unchanged=True)))
            self.rows.append(idle)
            self.data = b"".join(encoded(r) for r in self.rows)
            self.checkpoint = encoded(dict(schema_version=1, run_id="run", request_id=request["request_id"],
                sequence=len(self.rows), success=True, byte_count=len(self.data), sha256=hashlib.sha256(self.data).hexdigest()))

    def download(self, name, deadline, **kwargs):
        return self.data if name == "events.jsonl" else self.checkpoint

    def invoke(self):
        return physical_capture.Collector.cleanup_idle(self.collector, self.folder, IDENTITY, 140)

    def test_background_activation_and_fresh_idle_preserve_original_failure(self):
        proof = self.invoke()
        result = json.loads((self.folder / "reactivation-idle.json").read_bytes())
        self.assertTrue(result["reactivated"])
        self.assertFalse(result["runtime_acceptance"])
        self.assertEqual(result["deadline"], 130)
        self.assertEqual(proof["state"], "NATIVE_INPUT_IDLE")
        self.assertLess(self.operations.index("cleanup-reactivate-same-process"), self.operations.index("cleanup-idle-payload"))
        self.assertEqual(self.summary.read_bytes(), self.original_summary)
        self.assertTrue((self.folder / "native-events.jsonl").read_bytes().startswith(self.before))
        self.assertIn(b"human_failure", (self.folder / "before-reactivation.jsonl").read_bytes())

    def test_foreground_cleanup_needs_no_activation(self):
        self.rows[-1]["payload"]["scenes"][0]["activation"] = 0
        self.data = self.before = b"".join(encoded(r) for r in self.rows)
        self.invoke()
        self.assertNotIn("cleanup-reactivate-same-process", self.operations)
        self.assertFalse(json.loads((self.folder / "reactivation-idle.json").read_bytes())["reactivated"])

    def test_missing_or_stale_release_cannot_activate(self):
        self.clock = 121
        with self.assertRaises(Rejected): self.invoke()
        self.assertEqual(self.operations, [])
        (self.folder / "operator-released.json").unlink()
        with self.assertRaises(FileNotFoundError): self.invoke()
        self.assertEqual(self.operations, [])

    def test_foreign_release_cannot_activate(self):
        path = self.folder / "operator-released.json"
        reply = json.loads(path.read_bytes()); reply["run_id"] = "other"; path.write_bytes(encoded(reply))
        with self.assertRaises(Rejected): self.invoke()
        self.assertEqual(self.operations, [])

    def test_changed_pid_or_executable_never_activates(self):
        self.process["executable"] = "file:///replaced/UIKitTransitions.app/UIKitTransitions"
        with self.assertRaisesRegex(Rejected, "ended or changed"): self.invoke()
        self.assertNotIn("cleanup-reactivate-same-process", self.operations)
        self.assertNotIn("cleanup-idle-payload", self.operations)

    def test_activation_replacement_never_authorizes_idle_or_teardown(self):
        self.activation["result"]["process"]["processIdentifier"] = 13
        with self.assertRaisesRegex(Rejected, "replaced"): self.invoke()
        self.assertNotIn("cleanup-idle-payload", self.operations)
        self.assertFalse((self.folder / "reactivation-idle.json").exists())

    def test_activation_failure_or_late_return_cannot_publish_success(self):
        self.activation["info"]["outcome"] = "failed"
        with self.assertRaisesRegex(Rejected, "failed"): self.invoke()
        self.assertFalse((self.folder / "reactivation-idle.json").exists())

    def test_late_activation_keeps_the_original_budget(self):
        original = self.command
        def late(*args):
            value = original(*args); self.clock = 131; return value
        self.remote.command = late
        with self.assertRaises(Rejected): self.invoke()
        self.assertNotIn("cleanup-idle-payload", self.operations)
        self.assertFalse((self.folder / "reactivation-idle.json").exists())

    def test_foreign_source_in_preactivation_stream_never_activates(self):
        self.rows[0]["payload"]["source"] = "other"
        self.data = self.before = b"".join(encoded(r) for r in self.rows)
        with self.assertRaisesRegex(Rejected, "launch changed"): self.invoke()
        self.assertNotIn("cleanup-reactivate-same-process", self.operations)

    def test_changed_prefix_after_activation_is_preserved_but_rejected(self):
        original = self.push
        def changed(*args):
            if args[3] == "cleanup-idle-publish": self.rows[1]["payload"]["reason"] = "changed"
            return original(*args)
        self.remote.push = changed
        with self.assertRaisesRegex(Rejected, "preactivation evidence"): self.invoke()
        self.assertFalse((self.folder / "reactivation-idle.json").exists())
        self.assertEqual((self.folder / "before-reactivation.jsonl").read_bytes(), self.before)

    def test_active_input_does_not_authorize_teardown(self):
        original = self.push
        def held(*args):
            original(*args)
            if args[3] == "cleanup-idle-publish":
                self.rows[-1]["payload"]["input_state"]["pans"][0]["touches"] = 1
                self.data = b"".join(encoded(r) for r in self.rows)
                value = json.loads(self.checkpoint); value.update(byte_count=len(self.data), sha256=hashlib.sha256(self.data).hexdigest())
                self.checkpoint = encoded(value)
        self.remote.push = held
        with self.assertRaisesRegex(Rejected, "still active"): self.invoke()
        self.assertFalse((self.folder / "reactivation-idle.json").exists())

    def test_changed_or_transient_scene_prevents_activation(self):
        self.rows[-1]["payload"]["scenes"][0]["activation"] = 1
        self.data = self.before = b"".join(encoded(r) for r in self.rows)
        with self.assertRaisesRegex(Rejected, "bound foreground or background"): self.invoke()
        self.assertNotIn("cleanup-reactivate-same-process", self.operations)

    def test_expired_cleanup_permits_no_remote_action(self):
        with self.assertRaises(Rejected): physical_capture.Collector.cleanup_idle(self.collector, self.folder, IDENTITY, 99)
        self.assertEqual(self.operations, [])


if __name__ == "__main__": unittest.main()
