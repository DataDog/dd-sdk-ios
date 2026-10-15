#!/usr/bin/env python3
"""C03 only: genuine older-SDK legacy builds, with fresh boundary evidence."""
import copy
from datetime import datetime, timezone
import itertools
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

import analyze
import lifecycle
import run as baseline

REPO = baseline.REPO
HERE = Path(__file__).resolve().parent
DEFINITION = REPO / "DatadogRUM/MultiSceneSupport/Results/EXP-189-legacy-build-sdk.json"
BUILD_DEVELOPER = "/Applications/Xcode.app/Contents/Developer"
RUNTIME_DEVELOPER = "/Applications/Xcode_27.app/Contents/Developer"
MODES = ("automatic", "manual", "lifecycle-automatic", "lifecycle-manual")
VERSIONS = ("27.0", "26.5")
ARMS = ("baseline", "candidate")
ACTIVE = "UIApplicationDidBecomeActiveNotification"
BACKGROUND = "UIApplicationDidEnterBackgroundNotification"
FOREGROUND = "UIApplicationWillEnterForegroundNotification"


def now():
    return datetime.now(timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def unique_views(rows):
    values = {}
    for row in rows:
        if row["type"] == "view" and row["name"] != "ApplicationLaunch":
            values.setdefault(row["id"], row)
    return list(values.values())


def markers(rows, phase):
    return [(i, row) for i, row in enumerate(rows)
            if row["type"] in ("action", "resource")
            and (row.get("name") == phase or row.get("url") == "https://fixture.invalid/" + phase)]


def check_markers(rows, phase, owner):
    found = markers(rows, phase)
    require(sorted(row["type"] for _, row in found) == ["action", "resource"],
            "wrong marker cardinality: " + phase)
    require(all(row["owner"] == owner for _, row in found), "wrong owner: " + phase)
    return [i for i, _ in found]


def check_ready(data, run_id):
    require(data.get("run_id") == run_id, "stale readiness identity")
    require(data.get("failures") == [], "fixture failed before readiness")
    rows = data["events"]
    views = unique_views(rows)
    require([v["name"] for v in views] == ["Home"], "readiness lacks exact initial Home")
    check_markers(rows, "BeforeBackground", views[0]["id"])
    require(sum(r["type"] in ("action", "resource") for r in rows) == 2,
            "unexpected readiness markers")
    require(not any(r["type"] == "error" for r in rows), "error before readiness")
    require(not any(r.get("name") in (BACKGROUND, FOREGROUND) for r in rows),
            "readiness was consumed after the critical boundary")


def check_result(data, run_id, mode, version):
    require(data.get("run_id") == run_id, "stale terminal identity")
    require(data.get("mode") == mode and data.get("os") == version, "wrong mode or runtime")
    require(data.get("fixture_version") == 1, "wrong fixture version")
    require(data.get("has_scene_manifest") is False, "legacy manifest proof missing")
    require(data.get("failures") == [], "fixture failures")
    rows = data["events"]
    views = unique_views(rows)
    stopped = [any(r["type"] == "view" and r.get("id") == v["id"]
                   and r.get("active") is False for r in rows) for v in views]
    if mode in ("automatic", "manual"):
        require(not analyze.compatibility(data), "navigation ownership/occurrence oracle failed")
        require(stopped == [True, True, False], "wrong navigation stop/fresh-view state")
    else:
        manual = mode == "lifecycle-manual"
        require([v["name"] for v in views] == (["Home"] if manual else ["Home", "Home"]),
                "wrong lifecycle occurrence inventory")
        require(stopped == ([False] if manual else [True, False]), "wrong lifecycle stop state")
        before = check_markers(rows, "BeforeBackground", views[0]["id"])
        after = check_markers(rows, "AfterForeground", views[-1]["id"])
        require(sum(r["type"] in ("action", "resource") for r in rows) == 4,
                "unexpected lifecycle markers")
        require(not any(r["type"] == "error" for r in rows), "RUM error emitted")
        notifications = [(i, r["name"]) for i, r in enumerate(rows) if r["type"] == "lifecycle"]
        require([name for _, name in notifications] == [ACTIVE, BACKGROUND, FOREGROUND, ACTIVE],
                "missing, duplicated or reordered actual lifecycle")
        require(max(before) < notifications[1][0] < notifications[2][0] < notifications[3][0] < min(after),
                "markers straddle the wrong lifecycle boundary")
    ids = {v["id"]: i for i, v in enumerate(views)}
    return {
        "view_names": [v["name"] for v in views],
        "view_ids": [v["id"] for v in views],
        "stopped": stopped,
        "owners": [{"kind": r["type"], "phase": r.get("name", r.get("url")),
                    "occurrence": ids.get(r["owner"], -1)}
                   for r in rows if r["type"] in ("action", "resource")],
        "notifications": [r["name"] for r in rows if r["type"] == "lifecycle"],
    }


def matrix_verdict(cases):
    expected = set(itertools.product(ARMS, VERSIONS, MODES))
    keys = [(c["arm"], c["os"], c["mode"]) for c in cases]
    if len(keys) != len(set(keys)) or len({c["run_id"] for c in cases}) != len(cases):
        return "FAIL"
    if any(c["status"] == "FAIL" for c in cases):
        return "FAIL"
    if set(keys) != expected or any(c["status"] != "PASS" for c in cases):
        return "INCONCLUSIVE"
    if not all(c.get("installed_identity") and c.get("clean_install")
               and c.get("cleanup", {}).get("status") == "PASS" for c in cases):
        return "INCONCLUSIVE"
    for version, mode in itertools.product(VERSIONS, MODES):
        pair = [c["signature"] for c in cases if c["os"] == version and c["mode"] == mode]
        normalized = [{k: v for k, v in s.items() if k != "view_ids"} for s in pair]
        if normalized[0] != normalized[1]:
            return "FAIL"
    return "PASS"


def check_boundaries(item):
    keys = ("launched_at", "readiness_accepted_at", "background_command_started_at",
            "background_observed_at", "foreground_command_started_at",
            "foreground_command_finished_at", "finished_at")
    times = [datetime.fromisoformat(item[key]) for key in keys]
    require(all(value.tzinfo is not None for value in times), "boundary time lacks timezone")
    require(times == sorted(times), "critical assertions ran after their transition")


def compatibility_source(text):
    # C03 never executes the separate performance/retention workload.
    start = text.index('        if mode == "internal" {')
    end = text.index('        result["failures"] = failures', start)
    removed = text[start:end]
    require(removed.count("InternalFixture.run") == 1
            and text.count("InternalFixture.run") == 1, "internal-only fixture anchor changed")
    return text[:start] + text[end:]


def observed_lifecycle_source(text):
    text = lifecycle.app_variant(text)
    ready = '["run_id": value("--run-id")]'
    require(text.count(ready) == 1, "ready fixture anchor changed")
    text = text.replace(ready, '["run_id": value("--run-id"), "events": EventStore.shared.snapshot(), "failures": failures]')
    observer = '                EventStore.shared.append(["type": "lifecycle", "name": value.name.rawValue])'
    require(text.count(observer) == 1, "lifecycle observer anchor changed")
    return text.replace(observer, observer + '''
                let evidence: [String: Any] = ["run_id": Fixture.value("--run-id"), "events": EventStore.shared.snapshot()]
                try? JSONSerialization.data(withJSONObject: evidence).write(
                    to: Fixture.output.deletingLastPathComponent().appendingPathComponent("lifecycle-observations.json"),
                    options: .atomic
                )''')


def crash_time(value):
    try:
        result = datetime.fromisoformat(value)
    except ValueError:
        result = datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%f %z")
    require(result.tzinfo is not None, "crash time lacks timezone")
    return result.astimezone(timezone.utc)


class Runner:
    def __init__(self):
        sys.path.insert(0, str(REPO / "tools/multi-scene/acceptance"))
        import acceptance
        self.protected_state = acceptance.protected_state
        self.protected = self.protected_state(REPO)
        self.definition = json.loads(DEFINITION.read_text())
        self.root = Path(tempfile.mkdtemp(prefix="exp189-legacy-sdk26-"))
        self.attempt = self.root / "builds"
        self.summary = {
            "experiment": "EXP-189", "gate": "C03", "run_id": "exp189-" + str(uuid.uuid4()),
            "implementation_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
            "artifact_root": str(self.root), "started_at": now(), "status": "RUNNING",
            "definition_sha256": baseline.digest(DEFINITION), "commands": [], "cases": [],
            "builds": {}, "devices": {}, "gates_closed": [],
        }
        self.inputs = [HERE / name for name in ("legacy_compatibility.py", "run.py", "lifecycle.py", "analyze.py")]
        self.inputs += sorted((HERE / "Fixture").iterdir()) + [DEFINITION]
        require(not subprocess.check_output(["git", "status", "--porcelain", "--",
                    *[str(p.relative_to(REPO)) for p in self.inputs]], cwd=REPO, text=True).strip(),
                "runner inputs must be committed before execution")
        self.summary["inputs"] = {str(p.relative_to(REPO)): baseline.digest(p) for p in self.inputs}
        self.manifest = None
        self.booted = set()
        self.save()
        print(json.dumps({"artifact_root": str(self.root), "run_id": self.summary["run_id"]}), flush=True)

    def save(self):
        write_json(self.root / "summary.json", self.summary)

    def command(self, name, args, developer=RUNTIME_DEVELOPER, check=True):
        index = len(self.summary["commands"])
        stem = self.root / f"{index:03d}-{name}"
        row = {"name": name, "args": [str(a) for a in args], "developer_directory": developer,
               "started_at": now()}
        self.summary["commands"].append(row)
        self.save()
        with stem.with_suffix(".stdout").open("w") as out, stem.with_suffix(".stderr").open("w") as err:
            result = subprocess.run(row["args"], cwd=REPO, env=dict(os.environ, DEVELOPER_DIR=developer),
                                    stdout=out, stderr=err)
        row.update(exit_code=result.returncode, finished_at=now(),
                   stdout=str(stem.with_suffix(".stdout")), stderr=str(stem.with_suffix(".stderr")))
        self.save()
        if check:
            require(result.returncode == 0, f"{name} failed ({result.returncode}); see {stem}")
        return result.returncode, stem.with_suffix(".stdout").read_text()

    def preflight(self):
        processes = subprocess.check_output(["ps", "-axo", "comm="], text=True).splitlines()
        require(not any(Path(name.strip()).name == "xcodebuild" for name in processes),
                "another xcodebuild is active")
        _, toolchain = self.command("build-xcode", ["xcodebuild", "-version"], BUILD_DEVELOPER)
        _, sdk = self.command("build-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], BUILD_DEVELOPER)
        _, compiler = self.command("build-compiler", ["xcrun", "swiftc", "--version"], BUILD_DEVELOPER)
        _, runtime_xcode = self.command("runtime-xcode", ["xcodebuild", "-version"])
        require(sdk.strip() == "26.5" and "Xcode 26.6" in toolchain, "wrong genuine build toolchain")
        self.summary["environment"] = {"build_xcode": toolchain.strip(), "build_sdk": sdk.strip(),
                                       "swift": compiler.strip(), "runtime_xcode": runtime_xcode.strip()}
        _, raw = self.command("runtimes", ["xcrun", "simctl", "list", "runtimes", "--json"])
        runtimes = json.loads(raw)["runtimes"]
        _, raw = self.command("devices", ["xcrun", "simctl", "list", "devices", "available", "--json"])
        devices = json.loads(raw)["devices"]
        for version in VERSIONS:
            matches = [r for r in runtimes if r.get("isAvailable") and r.get("version") == version
                       and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
            require(len(matches) == 1, "runtime identity unavailable: " + version)
            runtime = matches[0]
            options = [d for d in devices.get(runtime["identifier"], []) if d["name"].startswith("iPhone")
                       and d["state"] in ("Shutdown", "Booted")]
            options.sort(key=lambda d: (d["state"] != "Shutdown", d["name"], d["udid"]))
            require(bool(options), "iPhone simulator unavailable: " + version)
            self.summary["devices"][version] = {
                **{k: options[0][k] for k in ("udid", "name", "state")},
                "runtime": runtime["identifier"], "runtime_build": runtime["buildversion"],
            }
        baseline.REVISIONS = {a: self.definition[a + "_revision"] for a in ARMS}
        baseline.ENV = dict(os.environ, DEVELOPER_DIR=BUILD_DEVELOPER)
        self.manifest = baseline.prepare(self.attempt)
        self.summary["source_fingerprints"] = {
            a: {k: v for k, v in x["sdk_sources"].items() if k != "files"}
            for a, x in self.manifest["arms"].items()
        }
        self.summary["source_revisions"] = baseline.REVISIONS
        self.summary["original_fixture"] = {k: v for k, v in self.manifest["fixture"].items() if k != "files"}
        for arm in ARMS:
            directory = self.attempt / arm
            navigation_source = directory / "Sources/App.swift"
            navigation_source.write_text(compatibility_source(navigation_source.read_text()))
            (directory / "Sources/InternalFixture.swift").unlink()
            lifecycle_sources = directory / "LifecycleSources"
            shutil.copytree(directory / "Sources", lifecycle_sources)
            (lifecycle_sources / "App.swift").write_text(observed_lifecycle_source((directory / "Sources/App.swift").read_text()))
            spec = json.loads((directory / "project.json").read_text())
            legacy = spec["targets"]["FixtureLegacy"]
            legacy["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"] = "com.datadoghq.exp189." + arm + ".legacy"
            observed = copy.deepcopy(legacy)
            observed["sources"] = ["LifecycleSources"]
            observed["settings"]["base"]["SWIFT_OBJC_BRIDGING_HEADER"] = "LifecycleSources/AllocationCounter.h"
            observed["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"] = "com.datadoghq.exp189." + arm + ".lifecycle"
            spec["targets"] = {"FixtureLegacy": legacy, "FixtureLegacyLifecycle": observed}
            spec["schemes"] = {
                "EXP189Navigation": {"build": {"targets": {"FixtureLegacy": "all"}}},
                "EXP189Lifecycle": {"build": {"targets": {"FixtureLegacyLifecycle": "all"}}},
            }
            write_json(directory / "project.json", spec)
            self.command("generate-" + arm, ["xcodegen", "generate", "--spec", directory / "project.json",
                                            "--project", directory], BUILD_DEVELOPER)
        self.save()

    def build(self, arm, variant):
        directory = self.attempt / arm
        name = "FixtureLegacy" + ("Lifecycle" if variant == "Lifecycle" else "")
        scheme = "EXP189" + variant
        print(json.dumps({"stage": "build", "arm": arm, "variant": variant}), flush=True)
        self.command("build-" + arm + "-" + variant, [
            "xcodebuild", "build", "-project", directory / "EXP160.xcodeproj",
            "-scheme", scheme, "-configuration", "Release", "-sdk", "iphonesimulator26.5",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", directory / "derived",
            "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
        ], BUILD_DEVELOPER)
        app = directory / "derived/Build/Products/Release-iphonesimulator" / (name + ".app")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        binary = app / info["CFBundleExecutable"]
        _, build_version = self.command("build-version", ["xcrun", "vtool", "-show-build", binary], BUILD_DEVELOPER)
        _, uuids = self.command("build-uuid", ["xcrun", "dwarfdump", "--uuid", binary], BUILD_DEVELOPER)
        require("UIApplicationSceneManifest" not in info, "build acquired scene manifest")
        require(info.get("DTSDKName") == "iphonesimulator26.5", "plist SDK mismatch")
        require(info.get("MinimumOSVersion") == "15.0", "deployment target changed")
        require(re.search(r"^\s*sdk 26\.5\s*$", build_version, re.M)
                and re.search(r"^\s*minos 15\.0\s*$", build_version, re.M), "Mach-O SDK/deployment mismatch")
        found_uuid = re.findall(r"UUID: ([A-Fa-f0-9-]+) \(arm64\)", uuids)
        require(len(found_uuid) == 1, "arm64 UUID missing")
        sources = directory / ("LifecycleSources" if variant == "Lifecycle" else "Sources")
        self.summary["builds"][arm + "/" + variant] = {
            "app": str(app), "executable": binary.name, "bundle": info["CFBundleIdentifier"],
            "sha256": baseline.digest(binary), "uuid": found_uuid[0].lower(),
            "sdk": info["DTSDKName"], "minimum_os": info["MinimumOSVersion"],
            "fixture": baseline.fingerprint(sources), "mach_o_build_version": build_version.strip(),
        }
        self.save()

    def boot(self, version):
        device = self.summary["devices"][version]
        if device["state"] == "Shutdown" and version not in self.booted:
            self.command("boot", ["xcrun", "simctl", "boot", device["udid"]])
            self.booted.add(version)
            self.command("boot-status", ["xcrun", "simctl", "bootstatus", device["udid"], "-b"])

    def wait_json(self, path, launched_ns, timeout=45):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if path.exists():
                require(path.stat().st_mtime_ns >= launched_ns, "stale fixture file timestamp")
                try:
                    return json.loads(path.read_text())
                except json.JSONDecodeError:
                    pass
            time.sleep(0.1)
        raise TimeoutError("No fresh fixture result: " + path.name)

    def collect_crash(self, item, build, directory):
        matches = []
        for path in Path.home().joinpath("Library/Logs/DiagnosticReports").glob("FixtureLegacy*.ips"):
            try:
                lines = path.read_text().splitlines()
                header, body = json.loads(lines[0]), json.loads("\n".join(lines[1:]))
                if (header.get("bundleID") != build["bundle"] or body.get("pid") != item.get("pid")
                        or header.get("slice_uuid", "").lower() != build["uuid"]):
                    continue
                captured = crash_time(body["captureTime"])
                if not datetime.fromisoformat(item["launched_at"]) <= captured <= datetime.now(timezone.utc):
                    continue
                preserved = directory / path.name
                shutil.copyfile(path, preserved)
                matches.append({
                    "path": str(preserved), "sha256": baseline.digest(preserved),
                    "capture_time": captured.isoformat(), "pid": body["pid"], "uuid": build["uuid"],
                    "exception": body.get("exception"),
                    "triggered_symbols": [f.get("symbol", "<unknown>") for t in body.get("threads", [])
                                          if t.get("triggered") for f in t.get("frames", [])[:8]],
                })
            except (ValueError, KeyError, IndexError):
                continue
        item["crash_evidence"] = matches

    def cleanup(self, device, bundle):
        self.command("cleanup-terminate", ["xcrun", "simctl", "terminate", device, bundle], check=False)
        _, jobs = self.command("cleanup-processes", ["xcrun", "simctl", "spawn", device, "launchctl", "list"])
        live = [line for line in jobs.splitlines() if bundle in line and line.split()[0].isdigit()]
        require(not live, "fixture process survives cleanup")
        self.command("cleanup-uninstall", ["xcrun", "simctl", "uninstall", device, bundle])
        code, _ = self.command("cleanup-data", ["xcrun", "simctl", "get_app_container", device, bundle, "data"], check=False)
        require(code != 0, "fixture data survives cleanup")
        return {"status": "PASS", "process_absent": True, "data_container_absent": True}

    def run_case(self, arm, version, mode):
        variant = "Lifecycle" if mode.startswith("lifecycle-") else "Navigation"
        build = self.summary["builds"][arm + "/" + variant]
        device = self.summary["devices"][version]["udid"]
        self.boot(version)
        run_id = "exp189-" + str(uuid.uuid4())
        directory = self.root / run_id
        directory.mkdir()
        item = {"run_id": run_id, "arm": arm, "os": version, "mode": mode,
                "status": "RUNNING", "binary_sha256": build["sha256"], "artifact_root": str(directory)}
        self.summary["cases"].append(item)
        bundle = build["bundle"]
        try:
            require(baseline.digest(Path(build["app"]) / build["executable"]) == build["sha256"], "frozen binary changed")
            self.command("prior-terminate", ["xcrun", "simctl", "terminate", device, bundle], check=False)
            self.command("prior-uninstall", ["xcrun", "simctl", "uninstall", device, bundle], check=False)
            code, _ = self.command("prior-data", ["xcrun", "simctl", "get_app_container", device, bundle, "data"], check=False)
            require(code != 0, "clean uninstall not proven")
            item["clean_install"] = True
            self.command("install", ["xcrun", "simctl", "install", device, build["app"]])
            _, raw = self.command("installed-app", ["xcrun", "simctl", "get_app_container", device, bundle, "app"])
            app = Path(raw.strip())
            info = plistlib.loads((app / "Info.plist").read_bytes())
            require("UIApplicationSceneManifest" not in info and info.get("DTSDKName") == build["sdk"],
                    "installed app SDK/manifest changed")
            require(baseline.digest(app / build["executable"]) == build["sha256"], "installed binary mismatch")
            item["installed_identity"] = True
            _, raw = self.command("installed-data", ["xcrun", "simctl", "get_app_container", device, bundle, "data"])
            documents = Path(raw.strip()) / "Documents"
            require(not (documents / "result.json").exists() and not (documents / "ready.json").exists(),
                    "fixture restored old output")
            launched_ns = time.time_ns()
            item["launched_at"] = now()
            _, raw = self.command("launch", ["xcrun", "simctl", "launch", "--arch=arm64",
                        "--stdout=" + str(directory / "app.stdout"), "--stderr=" + str(directory / "app.stderr"),
                        device, bundle, "--mode", mode, "--run-id", run_id])
            match = re.search(re.escape(bundle) + r": (\d+)", raw)
            require(match is not None, "normal launch did not return exact bundle/PID")
            item["pid"] = int(match.group(1))
            if variant == "Lifecycle":
                ready = self.wait_json(documents / "ready.json", launched_ns)
                check_ready(ready, run_id)
                require(not (documents / "result.json").exists(), "terminal assertion ran before OS boundary")
                write_json(directory / "accepted-readiness.json", ready)
                item["readiness"] = {"path": str(directory / "accepted-readiness.json"),
                                     "sha256": baseline.digest(directory / "accepted-readiness.json")}
                item["readiness_accepted_at"] = now()
                item["background_command_started_at"] = now()
                self.command("background", ["xcrun", "simctl", "launch", device, "com.apple.Preferences"])
                deadline = time.monotonic() + 10
                observed = None
                while time.monotonic() < deadline:
                    observed = self.wait_json(documents / "lifecycle-observations.json", launched_ns, timeout=2)
                    require(observed.get("run_id") == run_id, "stale lifecycle observation")
                    notifications = [r["name"] for r in observed["events"] if r["type"] == "lifecycle"]
                    if BACKGROUND in notifications:
                        require(not any(x == FOREGROUND for x in notifications), "foreground preceded driver")
                        break
                    time.sleep(0.1)
                else:
                    raise TimeoutError("No actual background before foreground command")
                write_json(directory / "accepted-background.json", observed)
                require(not (documents / "result.json").exists(), "terminal assertion ran before foreground")
                item["background"] = {"path": str(directory / "accepted-background.json"),
                                      "sha256": baseline.digest(directory / "accepted-background.json")}
                item["background_observed_at"] = now()
                item["foreground_command_started_at"] = now()
                self.command("foreground", ["xcrun", "simctl", "launch", device, bundle])
                item["foreground_command_finished_at"] = now()
            result = self.wait_json(documents / "result.json", launched_ns)
            write_json(directory / "result.json", result)
            item["signature"] = check_result(result, run_id, mode, version)
            item["result"] = {"path": str(directory / "result.json"), "sha256": baseline.digest(directory / "result.json")}
            item["status"] = "PASS"
        except Exception as error:
            item["status"] = "FAIL" if (directory / "result.json").exists() else "INCONCLUSIVE"
            item["error"] = str(error)
            if item.get("pid"):
                self.collect_crash(item, build, directory)
        finally:
            try:
                item["cleanup"] = self.cleanup(device, bundle)
            except Exception as error:
                item["cleanup"] = {"status": "INCONCLUSIVE", "error": str(error)}
                item["status"] = "INCONCLUSIVE"
            item["finished_at"] = now()
            self.save()
            print(json.dumps({k: item[k] for k in ("arm", "os", "mode", "status")}), flush=True)
        require(item["status"] == "PASS", "case did not pass; later cells are not admitted")

    def verify(self):
        require(self.protected_state(REPO) == self.protected, "protected user state changed")
        require(all(baseline.digest(REPO / path) == digest for path, digest in self.summary["inputs"].items()),
                "runner or fixture input changed during execution")
        for arm in ARMS:
            directory = self.attempt / arm
            require(all(baseline.digest(directory / "sdk" / path) == digest
                        for path, digest in self.manifest["arms"][arm]["sdk_sources"]["files"].items()),
                    "archived SDK changed")
        for key, build in self.summary["builds"].items():
            arm, variant = key.split("/")
            require(baseline.digest(Path(build["app"]) / build["executable"]) == build["sha256"], "built binary changed")
            path = self.attempt / arm / ("LifecycleSources" if variant == "Lifecycle" else "Sources")
            require(baseline.fingerprint(path) == build["fixture"], "built fixture source changed")
        for case in self.summary["cases"]:
            for key in ("readiness", "background"):
                if case.get(key):
                    artifact = case[key]
                    require(baseline.digest(Path(artifact["path"])) == artifact["sha256"],
                            "accepted boundary artifact changed")
            if case["status"] == "PASS" and case["mode"].startswith("lifecycle-"):
                check_boundaries(case)
                check_ready(json.loads(Path(case["readiness"]["path"]).read_text()), case["run_id"])
            if case.get("result"):
                artifact = case["result"]
                require(baseline.digest(Path(artifact["path"])) == artifact["sha256"], "result artifact changed")
                result = json.loads(Path(artifact["path"]).read_text())
                require(check_result(result, case["run_id"], case["mode"], case["os"]) == case["signature"],
                        "saved semantic result differs")
        self.summary["protected_paths_unchanged"] = True
        self.summary["frozen_inputs_verified"] = True

    def execute(self):
        try:
            self.preflight()
            self.build("baseline", "Navigation")
            self.run_case("baseline", "27.0", "automatic")
            self.summary["baseline_readiness"] = "PASS"
            self.build("candidate", "Navigation")
            for arm in ARMS:
                self.build(arm, "Lifecycle")
            for version, mode, arm in itertools.product(VERSIONS, MODES, ARMS):
                if (arm, version, mode) != ("baseline", "27.0", "automatic"):
                    self.run_case(arm, version, mode)
            self.verify()
            self.summary["status"] = matrix_verdict(self.summary["cases"])
        except Exception as error:
            self.summary["status"] = matrix_verdict(self.summary["cases"])
            if self.summary["status"] == "PASS":
                self.summary["status"] = "INCONCLUSIVE"
            self.summary["error"] = str(error)
        finally:
            restored = []
            for version in sorted(self.booted):
                device = self.summary["devices"][version]
                try:
                    self.command("restore-shutdown", ["xcrun", "simctl", "shutdown", device["udid"]])
                    _, raw = self.command("restored-devices", ["xcrun", "simctl", "list", "devices", "available", "--json"])
                    found = [d for rows in json.loads(raw)["devices"].values() for d in rows if d["udid"] == device["udid"]]
                    require(len(found) == 1 and found[0]["state"] == "Shutdown", "original shutdown state not restored")
                    restored.append(version)
                except Exception as error:
                    self.summary["status"] = "INCONCLUSIVE"
                    self.summary["restore_error"] = str(error)
            self.summary["restored_shutdown_runtimes"] = restored
            self.summary["protected_paths_unchanged"] = self.protected_state(REPO) == self.protected
            if not self.summary["protected_paths_unchanged"]:
                self.summary["status"] = "INCONCLUSIVE"
            self.summary["finished_at"] = now()
            self.summary["gate_status"] = self.summary["status"]
            self.summary["gates_closed"] = ["C03"] if self.summary["status"] == "PASS" else []
            self.summary["artifacts"] = {
                str(p.relative_to(self.root)): {"path": str(p), "sha256": baseline.digest(p)}
                for p in sorted(self.root.rglob("*")) if p.is_file()
                and "builds" not in p.relative_to(self.root).parts and p.name != "summary.json"
            }
            self.save()
            durable = REPO / "DatadogRUM/MultiSceneSupport/Results/acceptance" / (self.summary["run_id"] + ".json")
            require(not durable.exists(), "durable attempt already exists")
            compact = copy.deepcopy(self.summary)
            for key in ("commands", "artifacts"):
                artifact = self.root / (key + ".json")
                write_json(artifact, compact.pop(key))
                compact[key + "_inventory"] = {"path": str(artifact), "sha256": baseline.digest(artifact),
                                                "count": len(self.summary[key])}
            if self.manifest is not None:
                compact["source_manifest"] = {"path": str(self.attempt / "manifest.json"),
                                               "sha256": baseline.digest(self.attempt / "manifest.json")}
            write_json(durable, compact)
            print(json.dumps({"status": self.summary["status"], "gate": "C03", "durable_result": str(durable)}), flush=True)
        return self.summary["status"] == "PASS"


if __name__ == "__main__":
    raise SystemExit(0 if Runner().execute() else 1)
