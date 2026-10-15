"""Release-bound cleanup of a foreground or suspended physical fixture.

This path observes input idle for task removal only. It grants no scenario credit.
"""
import hashlib
import json
from pathlib import Path
import time

import physical_io as io
import physical_release as release
from capture_io import atomic, bounded_read, encoded

require = io.require


def stream(data, identity):
    require(data and data.endswith(b"\n"), "incomplete cleanup stream")
    rows = [json.loads(line) for line in data.splitlines()]
    require([r["sequence"] for r in rows] == list(range(1, len(rows) + 1)) and
            all(r["run_id"] == identity["run_id"] for r in rows), "foreign cleanup stream")
    launches = [r for r in rows if r["kind"] == "launch"]
    require(len(launches) == 1 and all(launches[0]["payload"][k] == identity[k]
            for k in ["pid", "source", "fixture", "nonce", "bundle"]), "cleanup launch changed")
    return rows


def original_process(collector, deadline):
    require(time.time() < deadline, "cleanup process check after deadline")
    require(isinstance(collector.process_path, str) and collector.process_path.endswith(
        "/" + collector.framework + "Transitions.app/" + collector.framework + "Transitions"),
        "original physical executable was not bound")
    values = [p for p in collector.remote.processes("cleanup-original-process", deadline)
              if p.get("processIdentifier") == collector.pid]
    require(len(values) == 1 and values[0].get("executable") == collector.process_path,
            "original cleanup process ended or changed")
    return values[0]


def prepare(collector, folder, identity, deadline):
    """Consume the real release before preserving bytes or reactivating the same PID."""
    folder = Path(folder)
    limit = min(deadline, time.time() + 30)
    require(time.time() + 1 < limit, "cleanup idle budget expired")
    request_raw = bounded_read(folder / "request.json", 16_384)
    reply_raw = bounded_read(folder / "operator-released.json", 16_384)
    request, reply = json.loads(request_raw), json.loads(reply_raw)
    require(request["kind"] == "HUMAN_RELEASE_REQUIRED" and request["run_id"] == identity["run_id"]
            and collector.run == identity["run_id"] and collector.pid == identity["pid"]
            and collector.bundle == identity["bundle"], "foreign cleanup release identity")
    release.validate_ack(request, request_raw, reply, time.time())
    original_process(collector, limit)
    prefix = collector.download("events.jsonl", limit)
    atomic(folder / "before-reactivation.jsonl", prefix)
    rows = stream(prefix, identity)
    geometry = [r for r in rows if r["kind"] == "geometry"]
    require(geometry, "cleanup activation state unavailable")
    scenes = geometry[-1]["payload"]["scenes"]
    require(len(scenes) == 1 and scenes[0]["id"] == collector.binding["scene"] and
            type(scenes[0]["activation"]) is int and scenes[0]["activation"] in [0, 2],
            "cleanup scene is not the bound foreground or background scene")
    backgrounded = scenes[0]["activation"] == 2
    result = dict(state="PREACTIVATION_CAPTURED", deadline=limit, run_id=identity["run_id"],
                  pid=identity["pid"], executable=collector.process_path,
                  prefix_sha256=hashlib.sha256(prefix).hexdigest(), prefix_bytes=len(prefix),
                  prefix_sequence=len(rows), release_request_sha256=hashlib.sha256(request_raw).hexdigest(),
                  operator_sha256=hashlib.sha256(reply_raw).hexdigest(), reactivated=backgrounded,
                  runtime_acceptance=False)
    atomic(folder / "preactivation.json", encoded(result))
    if backgrounded:
        # A valid release permits cleanup activation, never a new input/scenario.
        release.validate_ack(request, request_raw, reply, time.time())
        original_process(collector, limit)
        raw, _ = collector.remote.command(["device", "process", "launch", "--activate", collector.bundle],
                                          "cleanup-reactivate-same-process", limit)
        actual = io.returned(raw, collector.device, "devicectl.device.process.launch")
        process, options = actual["process"], actual["launchOptions"]
        require(actual["deviceIdentifier"] == collector.device and process["processIdentifier"] == collector.pid
                and process["executable"] == collector.process_path and options["activatedWhenStarted"] is True
                and options["terminateExistingInstances"] is False, "cleanup activation replaced original process")
        atomic(folder / "reactivation.json", encoded(dict(state="SAME_PROCESS_ACTIVATED", response=raw,
               observed_at=time.time(), deadline=limit, runtime_acceptance=False)))
        original_process(collector, limit)
    require(time.time() < limit, "cleanup preparation returned after deadline")
    return result


def finish(collector, folder, prepared, data, proof):
    """Keep preactivation and later idle evidence separate, with the prefix unchanged."""
    folder = Path(folder)
    prefix = bounded_read(folder / "before-reactivation.jsonl", prepared["prefix_bytes"])
    require(len(prefix) == prepared["prefix_bytes"] and hashlib.sha256(prefix).hexdigest() == prepared["prefix_sha256"]
            and data.startswith(prefix), "cleanup changed preactivation evidence")
    require(proof["sequence"] > prepared["prefix_sequence"], "cleanup idle predates release/reactivation")
    for name, key in [("request.json", "release_request_sha256"), ("operator-released.json", "operator_sha256")]:
        require(hashlib.sha256(bounded_read(folder / name, 16_384)).hexdigest() == prepared[key], "cleanup release changed")
    original_process(collector, prepared["deadline"])
    require(time.time() < prepared["deadline"], "late cleanup reactivation proof")
    result = dict(prepared, state="RELEASE_BOUND_NATIVE_IDLE", native=proof, finished_at=time.time())
    atomic(folder / "reactivation-idle.json", encoded(result))
    return result
