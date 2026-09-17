#!/usr/bin/env python3
"""Run the bounded multi-scene acceptance contract without storing credentials."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import uuid

SCENARIO = "actions.explicit-target.long-running-cross-scene-serial"
BUNDLE = "com.datadoghq.rum-native-multi-scene-probe"
PROBE = Path("Datadog/Example/MultiSceneProbe")
PROTECTED = ("Datadog/Datadog.xcodeproj/project.pbxproj",
             "xcconfigs/Datadog.local.xcconfig")
PREFIX = "long-running-"
PHASES = [
    ("long-running-representative-b", "scene-B", "scene-B", False),
    ("long-running-representative-a", "scene-A", "scene-A", False),
    ("long-running-finished-b", "scene-B", "scene-B", True),
    ("long-running-empty-b-representative-a", "scene-A", "scene-A", False),
    ("long-running-finished-a", "scene-A", "scene-A", True),
    ("long-running-legacy-representative-b", "scene-B", "scene-B", False),
    ("long-running-legacy-finished-b", "scene-B", "scene-A", True),
]
BATCH = [
    ("emit-scene-context-marker", "long-running-representative-b"),
    ("start-explicit-target-action", "long-running-shared"),
    ("start-explicit-target-action", "long-running-shared"),
    ("emit-scene-context-marker", "long-running-representative-a"),
    ("stop-explicit-target-action", "long-running-finished-b"),
    ("emit-scene-context-marker", "long-running-empty-b-representative-a"),
    ("stop-explicit-target-action", "long-running-empty-b"),
    ("stop-explicit-target-action", "long-running-finished-a"),
    ("emit-scene-context-marker", "long-running-legacy-representative-b"),
    ("start-legacy-action", "long-running-legacy-start"),
    ("stop-legacy-action", "long-running-legacy-finished-b"),
]


class Rejected(RuntimeError):
    def __init__(self, message, state="INVALID"):
        super().__init__(message)
        self.state = state


def require(value, message, state="INVALID"):
    if not value:
        raise Rejected(message, state)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".writing")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def protected_state(repo):
    """The local xcconfig is only stat'ed and its Git index entry inspected."""
    state = {}
    for relative in PROTECTED:
        p = repo / relative
        s = p.stat()
        state[relative] = {
            "inode": s.st_ino, "size": s.st_size, "mode": s.st_mode,
            "mtime_ns": s.st_mtime_ns, "ctime_ns": s.st_ctime_ns,
            "index": subprocess.check_output(
                ["git", "ls-files", "--stage", "--", relative], cwd=repo, text=True).strip()
        }
        if relative.endswith("project.pbxproj"):
            state[relative]["sha256"] = file_hash(p)
    return state


def source_identity(repo):
    roots = ["DatadogCore/Sources", "DatadogInternal/Sources", "DatadogRUM/Sources",
             "DatadogTrace/Sources", str(PROBE / "Sources"), str(PROBE / "Tests")]
    paths = set()
    for root in roots:
        paths.update(p for p in (repo / root).rglob("*") if p.is_file())
    paths.update(repo / p for p in [
        "Package.swift", str(PROBE / "project.yml"),
        str(PROBE / "RUMNativeMultiSceneProbe.xcodeproj/project.pbxproj"),
        str(PROBE / "RUMNativeMultiSceneProbe.xcodeproj/xcshareddata/xcschemes/RUMNativeMultiSceneProbe.xcscheme"),
    ] if (repo / p).is_file())
    paths.update(p for p in (repo / "tools/multi-scene/acceptance").glob("*")
                 if p.is_file() and p.suffix in {".py", ".js", ".json"})
    entries = {str(p.relative_to(repo)): file_hash(p) for p in sorted(paths)}
    require(not any(p in entries for p in PROTECTED), "protected path entered source inventory")
    return {"sha256": digest(entries), "file_count": len(entries), "files": entries}


def parse_records(raw):
    """Recover complete probe objects even when another log embeds them midline."""
    decoder = json.JSONDecoder()
    result = []
    for line in raw.splitlines():
        offset = 0
        while True:
            start = line.find("{", offset)
            if start < 0:
                break
            try:
                value, consumed = decoder.raw_decode(line[start:])
            except json.JSONDecodeError:
                offset = start + 1
                continue
            offset = start + consumed
            if isinstance(value, dict) and value.get("type") in {
                    "manifest", "signal", "semantic-result"}:
                result.append(value)
    return result


def require_before(signal, boundary, label):
    require(signal["sequence"] < boundary["sequence"], label + " arrived after its critical boundary", "FAIL")


def require_identity(actual, expected, label):
    require(actual == expected, "stale or changed " + label)


def unique(items, label):
    require(len(items) == 1, f"{label}: expected exactly one, received {len(items)}", "FAIL")
    return items[0]


def validate_local(records, run_id):
    manifests = [r["manifest"] for r in records if r["type"] == "manifest"]
    manifest = unique(manifests, "manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean", "stale or non-clean manifest")
    require(not manifest.get("validationErrors"), "manifest validation errors")
    scenario = manifest.get("scenario", {})
    require(scenario.get("identifier") == SCENARIO, "unsupported or stale scenario")
    require(scenario.get("requiredCapabilities") == ["multiple-scenes"], "scenario topology contract changed")
    require(len(scenario.get("expectedSemanticTimeline", [])) == 9 and
            len(scenario.get("completionConditions", [])) == 6, "stale fixture oracle")
    steps = scenario.get("steps", [])
    require(len(steps) == 5 and steps[-1].get("kind") == "run-continuous-action-target-batch",
            "stale fixture driver")
    # open-window owns B readiness. A subsequent B-ready wait would consume it twice.
    opened = set()
    for step in steps:
        if step.get("kind") == "open-window":
            opened.add(step.get("value"))
        if step.get("kind") == "wait-for-scene-ready":
            require(step.get("scene") not in opened, "readiness consumed twice")

    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals, "no probe signals")
    require(all(s.get("runID") == run_id and s.get("scenarioID") == SCENARIO for s in signals),
            "stale signal run/scenario identity")
    require(all(s.get("schemaVersion") == 5 for s in signals), "unsupported signal schema")
    sequences = [s["sequence"] for s in signals]
    require(sequences == list(range(1, len(signals) + 1)), "missing, duplicate or reordered signal sequence")
    terminals = [r for r in records if r["type"] == "semantic-result"]
    terminal = unique(terminals, "terminal result")
    require(terminal.get("runID") == run_id, "stale terminal run")
    result = terminal.get("result", {})
    require(result.get("scenarioID") == SCENARIO, "stale terminal scenario")
    state = result.get("state")
    require(state == "PASS", "app oracle did not pass: " + str(state),
            "INCONCLUSIVE" if state in {"INCONCLUSIVE", "SKIPPED"} else "FAIL")
    require(result.get("matchedExpectationCount") == 15 and result.get("issues") == [],
            "weak or incomplete app oracle", "FAIL")
    require(not any(s.get("kind") == "rum-error" for s in signals), "local RUM error", "FAIL")
    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-continuous-action-target-batch"], "batch boundary")
    substeps = [s for s in signals if s.get("kind") == "step-started" and
                "stepIndex" not in s and s["sequence"] > batch["sequence"]]
    require([(s.get("stepKind"), s.get("name")) for s in substeps] == BATCH,
            "critical batch calls changed or missing", "FAIL")
    for index, step in enumerate(substeps):
        if step["stepKind"] == "emit-scene-context-marker":
            continue
        upper = substeps[index + 1]["sequence"] if index + 1 < len(substeps) else len(signals) + 1
        submitted = [s for s in signals if s.get("kind") == "assertion" and
                     s.get("name") == "continuous-action-submitted-" + step["name"] and
                     step["sequence"] < s["sequence"] < upper]
        require(len(submitted) == 1 and submitted[0].get("result") == "PASS",
                "submission assertion outside critical call boundary: " + step["name"], "FAIL")

    contract = json.loads(Path(__file__).with_name("scenario-contract.json").read_text())
    require_identity(scenario, contract, "fixture contract")

    native, owners = {}, {}
    for scene in ["scene-A", "scene-B"]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 (s.get("semanticContext") or {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness: " + scene)
        require_before(ready[0], batch, "scene readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        require(native[scene], "missing native scene identity")
        homes = [s for s in signals if s.get("kind") == "rum-view-snapshot" and
                 (s.get("semanticContext") or {}).get("logicalSceneID") == scene and
                 (s.get("semanticContext") or {}).get("screen") == "home" and
                 s["sequence"] < batch["sequence"]]
        require(homes, "no Home snapshot before critical batch: " + scene, "FAIL")
        require(all(s.get("evidenceSource") == "rum-mapper" for s in homes),
                "call-site Home label substituted for mapper evidence")
        require(len({s["rumContext"].get("viewID") for s in homes}) == 1,
                "Home occurrence changed before critical batch: " + scene, "FAIL")
        live = homes[-1]
        require(live["rumContext"].get("viewActive") is True, "Home already ended before batch", "INCONCLUSIVE")
        owners[scene] = live["rumContext"].get("viewID")
    require(len(set(native.values())) == 2 and len(set(owners.values())) == 2, "scenes or occurrences alias", "FAIL")

    actions = [s for s in signals if s.get("kind") == "rum-action" and
               (s.get("sourceContext") or {}).get("phase", "").startswith(PREFIX)]
    require(len(actions) == len(PHASES), "missing, duplicate or early controlled action", "FAIL")
    expected = []
    for phase, owner, source, final in PHASES:
        signal = unique([s for s in actions if s["sourceContext"]["phase"] == phase], phase)
        require(signal.get("evidenceSource") == "rum-mapper", "call-site label substituted for mapper evidence")
        require(signal["rumContext"].get("viewID") == owners[owner], "wrong exact owner: " + phase, "FAIL")
        require(signal["sourceContext"].get("logicalSceneID") == source, "wrong source: " + phase, "FAIL")
        # Occurrence #1 is resolved from the first mapper Home UUID, not a
        # nonexistent occurrence field on native action envelopes.
        require(signal["sourceContext"].get("nativeSceneID") == native[source],
                "wrong native source: " + phase, "FAIL")
        action = signal.get("action", {})
        require(action.get("id") and action.get("type") == "custom", "missing action ID/type", "FAIL")
        if final:
            require(action.get("target") == phase and signal["sourceContext"].get("uptime") is not None,
                    "completion missing final name or stop metadata", "FAIL")
        expected.append({"phase": phase, "view_id": owners[owner], "source_scene": source,
                         "action_id": action["id"], "target": action.get("target"),
                         "uptime": signal["sourceContext"].get("uptime"),
                         "sequence": signal["sequence"], "duration_ns": action.get("loadingTimeNanoseconds")})
    require([e["sequence"] for e in expected] == sorted(e["sequence"] for e in expected),
            "wrong mapper completion/representative order", "FAIL")
    require(len({e["action_id"] for e in expected}) == 7, "reused action identity", "FAIL")
    sessions = {s["rumContext"]["sessionID"] for s in actions}
    require(len(sessions) == 1, "multiple RUM sessions in controlled batch", "FAIL")
    view_ids = {s["rumContext"]["viewID"] for s in signals
                if s.get("kind") == "rum-view-snapshot" and s.get("rumContext", {}).get("viewID")}
    require(len(view_ids) == 3 and set(owners.values()) < view_ids, "unexpected local view inventory", "FAIL")
    return {"assertions": 15, "session_id": sessions.pop(), "native_scenes": native,
            "owners": owners, "view_ids": sorted(view_ids), "actions": expected,
            "signal_count": len(signals), "simultaneous_visibility_claimed": False}


def validate_backend(local, run_id, actions, views, errors):
    """Rows are sanitized by the connector bridge, preserving exact semantic fields."""
    require(errors == 0, "backend error or crash evidence", "FAIL")
    require(len(views) == 3 and {v["view_id"] for v in views} == set(local["view_ids"]),
            "backend view inventory differs from mapper", "FAIL")
    require(all(v.get("run_id") == run_id and v.get("session_id") == local["session_id"] for v in views),
            "restored view run ID or wrong session hidden by run-filtered query", "FAIL")
    require(len(actions) == 7, "backend action count differs", "FAIL")
    for expected in local["actions"]:
        row = unique([a for a in actions if a.get("phase") == expected["phase"]], expected["phase"])
        for field in ["action_id", "view_id", "source_scene", "target"]:
            require(row.get(field) == expected.get(field), "backend " + field + " mismatch: " + expected["phase"], "FAIL")
        require(row.get("run_id") == run_id and row.get("session_id") == local["session_id"],
                "stale backend action identity", "FAIL")
        if expected["uptime"] is not None:
            require(abs(row.get("uptime", -1) - expected["uptime"]) < 0.000001,
                    "backend stop/phase time mismatch", "FAIL")
        if expected["duration_ns"] is not None:
            require(row.get("duration_ns") == expected["duration_ns"], "backend action duration differs", "FAIL")
    finals = [next(a for a in actions if a["phase"] == p) for p in
              ["long-running-finished-b", "long-running-finished-a", "long-running-legacy-finished-b"]]
    require(finals[0]["uptime"] < finals[1]["uptime"] < finals[2]["uptime"],
            "backend explicit stop order differs", "FAIL")
    return {"state": "PASS", "action_count": 7, "view_count": 3, "error_crash_count": 0}


def validate_bridge(request, response):
    require(response.get("request_id") == request["request_id"] and
            response.get("request_sha256") == digest(request), "stale backend bridge response")
    require(response.get("provider") == "datadog-mcp" and response.get("ok") is True,
            "backend connector failed", "INCONCLUSIVE")
    require(response.get("complete") is True, "backend response is truncated or unpaginated", "INCONCLUSIVE")
    require(response.get("query") == request["query"], "backend query provenance mismatch")
    return response["data"]


class Runner:
    def __init__(self, args):
        self.args = args
        self.repo = Path(args.repo).resolve()
        self.out = Path(args.output).resolve()
        require(not self.out.exists(), "output directory already exists; use a fresh run")
        self.out.mkdir(parents=True)
        (self.out / "bridge").mkdir()
        self.run_id = "exp161-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:12]
        self.environment = dict(os.environ, DEVELOPER_DIR=args.developer_dir)
        self.summary = {"schema_version": 1, "gate": "A01", "experiment": "EXP-161",
                        "run_id": self.run_id, "scenario_id": args.scenario, "started_at": now(),
                        "state": "RUNNING", "stages": {}, "artifacts": {}, "failures": []}
        self.protected = protected_state(self.repo)
        self.launch_process = None
        self.flush()

    def flush(self):
        save(self.out / "summary.json", self.summary)

    def command(self, argv, name, check=True, timeout=900):
        with (self.out / (name + ".log")).open("w") as log:
            result = subprocess.run(argv, cwd=self.repo, env=self.environment, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        if check:
            require(result.returncode == 0, name + " failed; inspect its scoped log", "INCONCLUSIVE")
        return result

    def capture(self, argv):
        return subprocess.check_output(argv, cwd=self.repo, env=self.environment, text=True, stderr=subprocess.DEVNULL)

    def commit_signature(self, revision):
        headers = self.capture(["git", "cat-file", "commit", revision]).split("\n\n", 1)[0]
        signed = any(line.startswith(("gpgsig ", "gpgsig-sha256 ")) for line in headers.splitlines())
        if signed:
            self.command(["git", "verify-commit", revision], "signature")
        return {"state": "VERIFIED" if signed else "UNSIGNED", "required_before_push": True}

    def stage(self, name, details):
        self.summary["stages"][name] = details
        self.flush()
        print(json.dumps({"stage": name, "state": details.get("state", "PASS"), "run_id": self.run_id}), flush=True)

    def exchange(self, kind, query):
        request = {"schema_version": 1, "request_id": str(uuid.uuid4()), "kind": kind,
                   "query": query, "from": self.summary["started_at"], "to": "now",
                   "run_id": self.run_id, "created_at": now()}
        path = self.out / "bridge" / (request["request_id"] + ".request.json")
        save(path, request)
        print(json.dumps({"backend_request": str(path), "kind": kind}), flush=True)
        response_path = path.with_name(request["request_id"] + ".response.json")
        deadline = time.monotonic() + self.args.backend_timeout
        while time.monotonic() < deadline:
            if response_path.exists():
                response = json.loads(response_path.read_text())
                return validate_bridge(request, response)
            time.sleep(0.5)
        raise Rejected("backend connector deadline expired: " + kind, "INCONCLUSIVE")

    def run(self):
        try:
            require(self.args.scenario == SCENARIO, "unsupported scenario: no generic acceptance claim")
            require(self.args.device, "explicit simulator UUID is required")
            self.summary["revision"] = self.capture(["git", "rev-parse", "HEAD"]).strip()
            self.summary["dirty_state"] = self.capture(["git", "status", "--porcelain=v1"]).splitlines()
            self.summary["commit_signature"] = self.commit_signature(self.summary["revision"])
            self.summary["xcode"] = self.capture(["xcodebuild", "-version"]).strip()
            devices = json.loads(self.capture(["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]
            matches = [(runtime, d) for runtime, ds in devices.items() for d in ds if d["udid"] == self.args.device]
            require(len(matches) == 1, "selected simulator unavailable", "INCONCLUSIVE")
            runtime, device = matches[0]
            require("iOS-27" in runtime, "scenario requires an iOS 27 simulator", "INCONCLUSIVE")
            self.summary["device"] = dict(device, runtime=runtime)
            auth = self.exchange("auth", "@context.probe.run_id:" + self.run_id + "-auth")
            require(auth.get("authenticated") is True, "Datadog read authentication failed", "INCONCLUSIVE")
            self.stage("preflight", {"state": "PASS", "authenticated_read": True})
            frozen = source_identity(self.repo)
            save(self.out / "source-identity.json", frozen)
            self.summary["source_fingerprint"] = frozen["sha256"]
            if device["state"] != "Booted":
                self.command(["xcrun", "simctl", "boot", self.args.device], "boot")
            self.command(["xcrun", "simctl", "bootstatus", self.args.device, "-b"], "boot-ready")
            derived = self.out / "derived"
            results = self.out / "probe.xcresult"
            self.command(["xcodebuild", "test", "-quiet", "-project", str(PROBE / "RUMNativeMultiSceneProbe.xcodeproj"),
                          "-scheme", "RUMNativeMultiSceneProbe", "-destination", "platform=iOS Simulator,id=" + self.args.device,
                          "-derivedDataPath", str(derived), "-resultBundlePath", str(results),
                          "-enableCodeCoverage", "NO", "CODE_SIGNING_ALLOWED=NO"], "build-tests", timeout=1200)
            tests = json.loads(self.capture(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(results)]))
            save(self.out / "test-summary.json", tests)
            require(tests.get("failedTests") == 0 and tests.get("passedTests", 0) >= 166 and
                    tests.get("skippedTests", 0) == 0 and tests.get("totalTestCount") == tests["passedTests"],
                    "incomplete/stale test artifact", "INVALID")
            require_identity(source_identity(self.repo), frozen, "source during build")
            app = derived / "Build/Products/Debug-iphonesimulator/RUMNativeMultiSceneProbe.app"
            info = plistlib.loads((app / "Info.plist").read_bytes())
            require(info.get("CFBundleIdentifier") == BUNDLE, "wrong app bundle")
            executable = info["CFBundleExecutable"]
            binary_sha = file_hash(app / executable)
            build = {"executable_sha256": binary_sha, "source_sha256": frozen["sha256"],
                     "uuid": self.capture(["xcrun", "dwarfdump", "--uuid", str(app / executable)]).strip()}
            save(self.out / "build-identity.json", build)
            self.stage("frozen_build", {"state": "PASS", "test_count": tests["passedTests"], **build})
            self.command(["xcrun", "simctl", "terminate", self.args.device, BUNDLE], "terminate-before", check=False)
            self.command(["xcrun", "simctl", "uninstall", self.args.device, BUNDLE], "uninstall", check=False)
            absence = self.command(["xcrun", "simctl", "get_app_container", self.args.device, BUNDLE, "data"],
                                   "container-absence", check=False)
            absent_text = (self.out / "container-absence.log").read_text()
            require(absence.returncode != 0 and ("No such file or directory" in absent_text or "not installed" in absent_text),
                    "clean-install absence not proven", "INCONCLUSIVE")
            self.command(["xcrun", "simctl", "install", self.args.device, str(app)], "install")
            installed = Path(self.capture(["xcrun", "simctl", "get_app_container", self.args.device, BUNDLE, "app"]).strip())
            require_identity(file_hash(installed / executable), binary_sha, "installed binary")
            self.stage("clean_install", {"state": "PASS", "data_container_absent": True,
                                        "installed_binary_sha256": binary_sha})
            console = self.out / "console.raw.log"
            with console.open("w") as output:
                self.launch_process = subprocess.Popen(
                    ["xcrun", "simctl", "launch", "--console-pty", self.args.device, BUNDLE,
                     "--probe-scenario", SCENARIO, "--probe-run-id", self.run_id, "--probe-run-mode", "clean"],
                    cwd=self.repo, env=self.environment, stdout=output, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + self.args.scenario_timeout
            records = []
            while time.monotonic() < deadline:
                records = parse_records(console.read_text(errors="replace"))
                if any(r["type"] == "semantic-result" for r in records):
                    break
                if self.launch_process.poll() is not None:
                    break
                time.sleep(0.25)
            require(any(r["type"] == "semantic-result" for r in records), "scenario has no terminal verdict", "INCONCLUSIVE")
            local = validate_local(records, self.run_id)
            (self.out / "probe.jsonl").write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in records))
            save(self.out / "local-evidence.json", local)
            require(source_identity(self.repo) == frozen, "source changed during scenario")
            require(file_hash(installed / executable) == binary_sha, "installed binary changed during scenario")
            self.stage("local_semantics", {"state": "PASS", **local})
            self.command(["xcrun", "simctl", "io", self.args.device, "screenshot", str(self.out / "terminal.png")],
                         "terminal-screenshot")
            # The bridge must paginate and retry intake within its deadline. It returns
            # source fields, never a hand-entered semantic verdict.
            sid = local["session_id"]
            actions = self.exchange("actions", f"@session.id:{sid} @type:action @context.probe.run_id:{self.run_id} @context.probe.phase:long-running-*")
            views = self.exchange("views", f"@session.id:{sid} @type:view")
            errors = self.exchange("errors", f"@session.id:{sid} (@type:error OR @view.crash.count:>0)")
            backend = validate_backend(local, self.run_id, actions, views, errors["count"])
            save(self.out / "backend-evidence.json", {"actions": actions, "views": views, "errors": errors})
            require(source_identity(self.repo) == frozen, "source changed during backend verification")
            self.stage("backend", backend)
            self.summary["state"] = "PASS"
        except Rejected as error:
            self.summary["state"] = error.state
            self.summary["failures"].append(str(error))
        except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
            self.summary["state"] = "INVALID"
            self.summary["failures"].append(type(error).__name__ + ": " + str(error))
        finally:
            if self.launch_process is not None:
                self.command(["xcrun", "simctl", "terminate", self.args.device, BUNDLE], "terminate-after", check=False)
                try:
                    self.launch_process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.launch_process.terminate()
            if protected_state(self.repo) != self.protected:
                self.summary["state"] = "INVALID"
                self.summary["failures"].append("protected workspace metadata/index changed")
            self.summary["finished_at"] = now()
            self.summary["artifacts"] = {p.name: str(p) for p in self.out.iterdir() if p.is_file()}
            self.summary["rerun"] = "Use a fresh output directory and freshly resolved device; do not reuse run IDs or bridge responses."
            self.flush()
            if self.args.durable_output:
                durable = Path(self.args.durable_output).resolve()
                durable.mkdir(parents=True, exist_ok=True)
                destination = durable / (self.run_id + ".json")
                require(not destination.exists(), "durable run summary already exists")
                record = dict(self.summary)
                record["source_file_count"] = locals().get("frozen", {}).get("file_count")
                record["oracle_contract_sha256"] = file_hash(Path(__file__).with_name("scenario-contract.json"))
                record["evidence"] = {}
                for name in ["build-identity.json", "test-summary.json", "local-evidence.json", "backend-evidence.json"]:
                    artifact = self.out / name
                    if artifact.exists():
                        record["evidence"][name] = json.loads(artifact.read_text())
                save(destination, record)
                print(json.dumps({"durable_summary": str(destination)}), flush=True)
            print(json.dumps({"state": self.summary["state"], "summary": str(self.out / "summary.json")}), flush=True)
        return 0 if self.summary["state"] == "PASS" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    parser.add_argument("--device", required=True)
    parser.add_argument("--output", required=True, help="New attempt directory, must not exist")
    parser.add_argument("--durable-output", help="Directory for unique, sanitized run summaries")
    parser.add_argument("--scenario", default=SCENARIO)
    parser.add_argument("--developer-dir", default="/Applications/Xcode_27.app/Contents/Developer")
    parser.add_argument("--scenario-timeout", type=int, default=120)
    parser.add_argument("--backend-timeout", type=int, default=300)
    args = parser.parse_args()
    return Runner(args).run()


if __name__ == "__main__":
    sys.exit(main())
