"""Local F08 request/checkpoint transport; no input, installation or gate acceptance."""
import hashlib
import json
import os
from pathlib import Path
import time
import uuid

from capture_contract import prefix, MAX_BYTES, identifier, loads, published_snapshot, require, STRICT_COST_POLICY, CORRECTNESS_COST_POLICY


def atomic(path, data, *, exclusive=True):
    path = Path(path)
    require(path.parent.is_dir() and not path.is_symlink(), "unprepared or symlinked output")
    temporary = path.with_name("." + path.name + "-" + uuid.uuid4().hex)
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if exclusive:
            os.link(temporary, path)
        else:
            os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def bounded_read(path, maximum):
    path = Path(path)
    require(not path.is_symlink(), "symlinked capture evidence")
    with path.open("rb") as stream:
        data = stream.read(maximum + 1)
    require(len(data) <= maximum, "capture evidence exceeds bound")
    return data


class Collector:
    def __init__(self, documents, output, identity, pid, live_process, *, deadline, snapshot_seconds=30, cost_policy=STRICT_COST_POLICY):
        require(cost_policy in {STRICT_COST_POLICY, CORRECTNESS_COST_POLICY}, "unknown observer cost policy")
        self.cost_policy = cost_policy
        self.documents = Path(documents).resolve(strict=True)
        self.output = Path(output).resolve(strict=True)
        require(self.documents.is_dir() and self.output.is_dir() and not list(self.output.iterdir()), "collector output not fresh")
        require(set(identity) == {"run_id", "nonce"} and all(identifier(v) for v in identity.values()), "invalid capture identity")
        require(type(pid) is int and pid > 0 and callable(live_process), "missing process binding")
        require(type(snapshot_seconds) in (int, float) and 0 < snapshot_seconds <= 30, "invalid snapshot budget")
        self.identity = dict(identity)
        self.pid, self.live_process = pid, live_process
        self.deadline = deadline
        self.monotonic_deadline = time.monotonic() + max(0, deadline - time.time())
        self.snapshot_seconds = snapshot_seconds
        self.directory = self.documents / ("rum-release-capture-" + identity["run_id"])
        require(not self.directory.is_symlink(), "symlinked native stream directory")
        self.request_path = self.documents / "release-capture-request.json"
        require(not self.request_path.exists() and not self.request_path.is_symlink(), "stale native request exists")
        self.phases, self.consumed = set(), set()
        self.last_prefix = b""
        self.last_sequence = 0
        self.last_snapshot = None
        # Prove both output publication and the native request publication directory.
        for directory in (self.output, self.documents):
            probe = directory / (".capture-publication-" + uuid.uuid4().hex)
            atomic(probe, b"publication-preflight")
            require(probe.read_bytes() == b"publication-preflight", "publication preflight differs")
            probe.unlink()

    def live(self, end, monotonic_end):
        require(time.time() < min(end, self.deadline) and time.monotonic() < min(monotonic_end, self.monotonic_deadline), "original capture deadline expired")
        require(self.live_process() is True, "original process identity no longer valid")

    def snapshot(self, phase, *, deadline):
        require(isinstance(phase, str) and 0 < len(phase) <= 128 and phase not in self.phases, "invalid or consumed capture phase")
        end = min(deadline, self.deadline, time.time() + self.snapshot_seconds)
        monotonic_end = time.monotonic() + max(0, end - time.time())
        self.live(end, monotonic_end)
        self.phases.add(phase)
        request = dict(schema_version=1, **self.identity, request_id=str(uuid.uuid4()), phase=phase)
        folder = self.output / request["request_id"]
        folder.mkdir(mode=0o700)
        raw_request = encoded(request)
        atomic(folder / "request.json", raw_request)
        started = time.time()
        receipt_path = self.directory / ("checkpoint-" + request["request_id"] + ".json")
        outcome = dict(state="INVALID", phase=phase, request_id=request["request_id"],
                       issued_at=started, deadline=end, runtime_acceptance=False)
        try:
            require(not receipt_path.exists(), "restored checkpoint exists before publication")
            atomic(self.request_path, raw_request, exclusive=False)
            published = time.time()
            while not receipt_path.exists():
                self.live(end, monotonic_end)
                time.sleep(min(0.05, max(0, monotonic_end - time.monotonic())))
            # Persist the actual returned bytes before decoding, even on invalid evidence.
            receipt_bytes = bounded_read(receipt_path, 16_384)
            stream_bytes = bounded_read(self.directory / "events.jsonl", MAX_BYTES)
            atomic(folder / "writer-checkpoint.json", receipt_bytes)
            atomic(folder / "observed-events.jsonl", stream_bytes)
            receipt = loads(receipt_bytes)
            result, row = published_snapshot(stream_bytes, receipt, raw_request, self.consumed, cost_policy=self.cost_policy)
            require(stream_bytes.startswith(self.last_prefix), "native durable prefix was replaced")
            require(row["sequence"] > self.last_sequence and row["fields"]["topology"]["pid"] == self.pid, "restored snapshot or wrong native process")
            self.live(end, monotonic_end)
            self.consumed.add(request["request_id"])
            self.last_prefix = stream_bytes[:receipt["byte_count"]]
            self.last_sequence = receipt["sequence"]
            self.last_snapshot = row
            outcome.update(state="DURABLE_SNAPSHOT", published_at=published, completed_at=time.time(),
                           native_snapshot_sequence=row["sequence"], prefix_sequence=receipt["sequence"],
                           prefix_sha256=receipt["sha256"], prefix_bytes=receipt["byte_count"],
                           request_sha256=hashlib.sha256(raw_request).hexdigest(),
                           writer_receipt_sha256=hashlib.sha256(receipt_bytes).hexdigest(), observer_cost=result["observer_cost"])
            value = (result, row, folder)
        except Exception as error:
            outcome.update(reason=str(error), completed_at=time.time())
            raise
        finally:
            atomic(folder / "capture.json", encoded(outcome))
        try:
            self.live(end, monotonic_end)
        except Exception as error:
            atomic(folder / "late-publication.json", encoded({"state": "INVALID", "reason": str(error), "finished_at": time.time(), "deadline": end}))
            raise
        return value

    def assert_ready(self, snapshot, *, deadline):
        """Call immediately before publishing the human prompt, after display capture."""
        require(self.last_snapshot is not None and snapshot == self.last_snapshot, "stale snapshot supplied as readiness")
        end = min(deadline, self.deadline)
        self.live(end, time.monotonic() + max(0, end - time.time()))
        raw = bounded_read(self.directory / "events.jsonl", MAX_BYTES)
        require(raw.startswith(self.last_prefix), "native prefix changed after capture")
        require(raw.endswith(b"\n"), "partial native write before prompt")
        # This is a readback validation boundary, not a replacement writer receipt.
        readback = dict(schema_version=1, identity=self.identity, request_id=snapshot["request_id"],
                        sequence=len(raw.splitlines()), success=True, byte_count=len(raw),
                        sha256=hashlib.sha256(raw).hexdigest())
        rows = prefix(raw, readback, self.identity, cost_policy=self.cost_policy)["rows"]
        later = [row for row in rows if row["sequence"] > snapshot["sequence"]]
        require(all(row.get("request_id") == snapshot["request_id"] and row.get("phase") == snapshot["phase"]
                    for row in later), "request or phase changed before prompt")
        require(later and later[0].get("kind") == "observer_cost" and
                later[0].get("fields", {}).get("event_sequence") == snapshot["sequence"], "snapshot cost missing before prompt")
        pending = later[1:]
        require(len(pending) % 2 == 0, "incomplete native observation before prompt")
        reference = snapshot.get("last_context_sequence")
        original = rows[reference - 1] if type(reference) is int and 0 < reference < snapshot["sequence"] else None
        for index in range(0, len(pending), 2):
            event, cost = pending[index:index + 2]
            require(event.get("kind") == "context" and cost.get("kind") == "observer_cost", "native readiness consumed before prompt")
            require(original is not None and original.get("kind") == "context" and event.get("fields") == original["fields"], "context owner or clock changed before prompt")
            fields = cost.get("fields", {})
            require(fields.get("event_sequence") == event["sequence"] and fields.get("operation") == "context"
                    and type(fields.get("duration_ns")) is int and 0 <= fields["duration_ns"]
                    and (self.cost_policy == CORRECTNESS_COST_POLICY or fields["duration_ns"] <= 2_000_000),
                    "unqualified pending context cost")
        self.live(end, time.monotonic() + max(0, end - time.time()))
        return {"state": "READY_TO_PUBLISH_PROMPT", "checked_at": time.time(), "snapshot_sequence": snapshot["sequence"],
                "observed_sequence": len(rows), "runtime_acceptance": False}
