import copy
import hashlib
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest import mock

import capture_io as transport
from test_capture_contract import IDENTITY, payload


class CaptureIOTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.documents = self.root / "Documents"
        self.output = self.root / "output"
        self.documents.mkdir(); self.output.mkdir()
        self.end = time.time() + 2

    def collector(self, **overrides):
        arguments = dict(deadline=self.end, snapshot_seconds=1)
        arguments.update(overrides)
        return transport.Collector(self.documents, self.output, IDENTITY, 12, lambda: True, **arguments)

    def native(self, *, wrong_pid=False, corrupt_digest=False, concurrent=True):
        stop = threading.Event()
        def worker():
            request_path = self.documents / "release-capture-request.json"
            while not stop.is_set():
                if not request_path.exists():
                    time.sleep(0.001);continue
                raw = request_path.read_bytes();request = json.loads(raw)
                entries = [("context", {}), ("snapshot", {"request_sha256": hashlib.sha256(raw).hexdigest(), "topology": {"pid": 99 if wrong_pid else 12, "app_state": 0}})]
                if concurrent:entries.append(("context", {}))
                rows, _ = payload(entries)
                for row in rows:
                    row.update(identity=IDENTITY, request_id=request["request_id"], phase=request["phase"])
                data = b"".join(transport.encoded(row) for row in rows)
                directory = self.documents / ("rum-release-capture-" + IDENTITY["run_id"])
                directory.mkdir()
                (directory / "events.jsonl").write_bytes(data)
                receipt = dict(schema_version=1, identity=IDENTITY, request_id=request["request_id"], sequence=len(rows), success=True,
                               byte_count=len(data), sha256="0" * 64 if corrupt_digest else hashlib.sha256(data).hexdigest())
                transport.atomic(directory / ("checkpoint-" + request["request_id"] + ".json"), transport.encoded(receipt))
                return
        thread = threading.Thread(target=worker)
        thread.start()
        self.addCleanup(lambda: (stop.set(), thread.join(timeout=1)))

    def later_context(self, result):
        event, cost = copy.deepcopy(result["rows"][-2:])
        for row in (event, cost):
            row["sequence"] += 2
            row["monotonic_ns"] += 200
            row["capture_started_ns"] += 200
            row["last_context_sequence"] = result["rows"][-2]["sequence"] if row is event else event["sequence"]
        cost["fields"]["event_sequence"] = event["sequence"]
        return event, cost

    def test_actual_snapshot_survives_concurrent_context_and_is_ready(self):
        collector = self.collector();self.native()
        result, snapshot, folder = collector.snapshot("list-ready", deadline=self.end)
        self.assertEqual(snapshot["sequence"], 3)
        self.assertEqual(result["rows"][-2]["kind"], "context")
        self.assertEqual(json.loads((folder / "capture.json").read_bytes())["state"], "DURABLE_SNAPSHOT")
        self.assertEqual(collector.assert_ready(snapshot, deadline=self.end)["state"], "READY_TO_PUBLISH_PROMPT")
        with self.assertRaisesRegex(ValueError, "consumed"):
            collector.snapshot("list-ready", deadline=self.end)

    def test_invalid_native_bytes_are_retained(self):
        collector = self.collector();self.native(corrupt_digest=True)
        with self.assertRaisesRegex(ValueError, "digest"):
            collector.snapshot("list-ready", deadline=self.end)
        folder = next(self.output.iterdir())
        self.assertTrue((folder / "observed-events.jsonl").is_file())
        self.assertTrue((folder / "writer-checkpoint.json").is_file())
        self.assertEqual(json.loads((folder / "capture.json").read_bytes())["state"], "INVALID")

    def test_foreign_native_process_is_not_readiness(self):
        collector = self.collector();self.native(wrong_pid=True)
        with self.assertRaisesRegex(ValueError, "process"):
            collector.snapshot("list-ready", deadline=self.end)

    def test_missing_receipt_expires_without_republishing(self):
        collector = self.collector(snapshot_seconds=0.04)
        with self.assertRaisesRegex(ValueError, "deadline"):
            collector.snapshot("list-ready", deadline=self.end)
        self.assertEqual(len(list(self.output.iterdir())), 1)
        with self.assertRaisesRegex(ValueError, "consumed"):
            collector.snapshot("list-ready", deadline=self.end)

    def test_prior_request_and_symlink_are_rejected(self):
        request = self.documents / "release-capture-request.json"
        request.write_text("old")
        with self.assertRaisesRegex(ValueError, "stale"):
            self.collector()
        request.unlink();request.symlink_to(self.root / "missing")
        with self.assertRaisesRegex(ValueError, "stale"):
            self.collector()

    def test_consumed_native_readiness_is_rejected(self):
        collector = self.collector();self.native()
        result, snapshot, _ = collector.snapshot("list-ready", deadline=self.end)
        row = copy.deepcopy(result["rows"][-1]);row.update(sequence=len(result["rows"]) + 1, kind="navigation_callback")
        with (collector.directory / "events.jsonl").open("ab") as stream:
            stream.write(transport.encoded(row))
        with self.assertRaises(ValueError):
            collector.assert_ready(snapshot, deadline=self.end)

    def test_replaced_prefix_and_stale_snapshot_fail(self):
        collector = self.collector();self.native()
        result, snapshot, _ = collector.snapshot("list-ready", deadline=self.end)
        with self.assertRaisesRegex(ValueError, "stale"):
            collector.assert_ready(dict(snapshot, sequence=100), deadline=self.end)
        (collector.directory / "events.jsonl").write_bytes(b"replaced")
        with self.assertRaisesRegex(ValueError, "prefix"):
            collector.assert_ready(snapshot, deadline=self.end)

    def test_semantic_rows_and_partial_tail_cannot_reuse_readiness(self):
        collector = self.collector();self.native()
        result, snapshot, _ = collector.snapshot("list-ready", deadline=self.end)
        original = (collector.directory / "events.jsonl").read_bytes()
        for kind in ("capture_failure", "manual_call", "mapper", "browser_message", "owned_webview", "predicate_result"):
            event = copy.deepcopy(result["rows"][-2]);event.update(sequence=len(result["rows"]) + 1, kind=kind)
            cost = copy.deepcopy(result["rows"][-1]);cost.update(sequence=len(result["rows"]) + 2)
            cost["fields"].update(event_sequence=event["sequence"], operation=kind)
            (collector.directory / "events.jsonl").write_bytes(original + transport.encoded(event) + transport.encoded(cost))
            with self.subTest(kind=kind), self.assertRaises(ValueError):collector.assert_ready(snapshot, deadline=self.end)
        (collector.directory / "events.jsonl").write_bytes(original + b"partial")
        with self.assertRaisesRegex(ValueError, "partial"):collector.assert_ready(snapshot, deadline=self.end)

    def test_changed_context_does_not_reuse_readiness(self):
        collector = self.collector();self.native()
        result, snapshot, _ = collector.snapshot("list-ready", deadline=self.end)
        original = (collector.directory / "events.jsonl").read_bytes()
        event, cost = self.later_context(result)
        event["fields"]["view_id"] = "foreign"
        (collector.directory / "events.jsonl").write_bytes(original + transport.encoded(event) + transport.encoded(cost))
        with self.assertRaisesRegex(ValueError, "context owner"):collector.assert_ready(snapshot, deadline=self.end)

    def test_later_context_requires_complete_clock_schema_and_references(self):
        collector = self.collector();self.native()
        result, snapshot, _ = collector.snapshot("list-ready", deadline=self.end)
        original = (collector.directory / "events.jsonl").read_bytes()
        pair = self.later_context(result)
        path = collector.directory / "events.jsonl"
        path.write_bytes(original + b"".join(transport.encoded(row) for row in pair))
        self.assertEqual(collector.assert_ready(snapshot, deadline=self.end)["state"], "READY_TO_PUBLISH_PROMPT")
        for index in (0, 1):
            for field, value in (("schema_version", None), ("monotonic_ns", 1), ("capture_started_ns", 0),
                                 ("wall_ms", 0), ("reservation_latency_ns", 999), ("last_context_sequence", 1),
                                 ("last_view_sequence", 99), ("identity", {})):
                changed = copy.deepcopy(pair);changed[index][field] = value
                path.write_bytes(original + b"".join(transport.encoded(row) for row in changed))
                with self.subTest(index=index, field=field), self.assertRaises(ValueError):
                    collector.assert_ready(snapshot, deadline=self.end)

    def test_publication_after_deadline_remains_invalid(self):
        collector = self.collector(snapshot_seconds=0.15);self.native()
        original = transport.atomic
        def delayed(path, data, **kwargs):
            original(path, data, **kwargs)
            if Path(path).name == "capture.json":time.sleep(0.2)
        with mock.patch.object(transport, "atomic", delayed), self.assertRaisesRegex(ValueError, "deadline"):
            collector.snapshot("list-ready", deadline=self.end)
        folder = next(self.output.iterdir())
        self.assertEqual(json.loads((folder / "late-publication.json").read_bytes())["state"], "INVALID")


if __name__ == "__main__":unittest.main()
