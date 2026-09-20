#!/usr/bin/env python3
"""EXP-195: isolated unchanged-app, compiler and SDK comparison."""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE.parent / "acceptance"))
from acceptance import protected_state
from installed_code import inventory
spec = importlib.util.spec_from_file_location("baseline", HERE.parent / "baselines/run.py")
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)
REVISIONS = {"baseline": "92f021ba7e4a866f84a52da93ed8b63f3dc75882", "candidate": "04201edc7711361279d8487b385bc8b0ca9c63c7"}
DEVELOPERS = {"26.5": "/Applications/Xcode.app/Contents/Developer", "27.1": "/Applications/Xcode_27.1.app/Contents/Developer"}
RUN_ENV = dict(os.environ, DEVELOPER_DIR=DEVELOPERS["27.1"])
DEFINITION = REPO / "DatadogRUM/MultiSceneSupport/Results/EXP-195-automatic-tracking.json"

def save(path, obj):
    path = Path(path); temp = path.with_suffix(path.suffix + ".writing")
    temp.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n"); temp.replace(path)

def call(command, *, env=RUN_ENV, cwd=None, log=None, check=True, timeout=120):
    if log:
        with open(log, "w") as output:
            p = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        out = ""
    else:
        p = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout); out = p.stdout.strip()
    if check and p.returncode: raise RuntimeError(f"exit {p.returncode}: {command}; log={log}; " + (p.stderr[-2000:] if not log else ""))
    return out

def app_metadata(app):
    data = (Path(app) / "Info.plist").read_bytes()
    info = plistlib.loads(data)
    return {"info_sha256": hashlib.sha256(data).hexdigest(), "build_sdk": info.get("DTSDKName"),
            "declared_multiple_scenes": info.get("UIApplicationSceneManifest", {}).get("UIApplicationSupportsMultipleScenes", False)}

def namespace(experiment):
    if not isinstance(experiment, str) or not re.fullmatch(r"EXP-[0-9]{3}", experiment):
        raise ValueError("explicit experiment identity required")
    return experiment.replace("-", "").lower()


def configuration(definition_path=None):
    definition = json.loads(Path(definition_path or DEFINITION).read_text())
    experiment = definition["experiment"]
    namespace(experiment)
    revisions = definition.get("source_revisions", REVISIONS if experiment == "EXP-195" else {})
    if set(revisions) != {"baseline", "candidate"}:
        raise ValueError("exact baseline/candidate revisions required")
    if any(not isinstance(r, str) or not re.fullmatch(r"[0-9a-f]{40}", r) for r in revisions.values()):
        raise ValueError("source revisions must be complete commit hashes")
    if experiment == "EXP-195" and revisions != REVISIONS:
        raise ValueError("historical experiment cannot use new source revisions")
    if revisions["baseline"] == revisions["candidate"]:
        raise ValueError("source comparison requires distinct revisions")
    for revision in revisions.values():
        if call(["git", "cat-file", "-t", revision], cwd=REPO) != "commit":
            raise ValueError("source revision is not a commit")
    if experiment != "EXP-195":
        if definition.get("defined_before_implementation") is not True:
            raise ValueError("experiment must be defined before implementation")
        if call(["git", "merge-base", *revisions.values()], cwd=REPO) != revisions["baseline"]:
            raise ValueError("candidate must descend from frozen develop")
    return experiment, revisions, definition


def helper_fingerprint():
    paths = sorted(set(HERE.glob("*.py")) | set((HERE.parent / "acceptance").glob("*.py"))
                   | {HERE.parent / "baselines/run.py"})
    return {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def validate_frozen_inputs(attempt, manifest):
    definition_bytes = (attempt / "definition.json").read_bytes()
    frozen_definition = json.loads(definition_bytes)
    if manifest.get("experiment", "EXP-195") == "EXP-195":
        if frozen_definition.get("experiment") != "EXP-195" or manifest.get("definition", {}).get("experiment") != "EXP-195":
            raise ValueError("historical experiment identity restored over another definition")
        return  # Historical definitions retain their original acceptance contract.
    namespace(manifest["experiment"])
    if hashlib.sha256(definition_bytes).hexdigest() != manifest.get("definition_sha256"):
        raise ValueError("frozen definition changed")
    if json.loads(definition_bytes) != manifest["definition"]:
        raise ValueError("manifest definition differs from frozen definition")
    if manifest["definition"].get("experiment") != manifest["experiment"]:
        raise ValueError("experiment identity differs from definition")
    if helper_fingerprint() != manifest.get("host_helpers"):
        raise ValueError("host helper source changed")
    if baseline.fingerprint(HERE / "Fixture") != manifest["fixture"] or baseline.fingerprint(HERE / "UITests") != manifest["ui_tests"]:
        raise ValueError("application or collector source changed")
    revisions = manifest["definition"]["source_revisions"]
    for key, build in manifest["builds"].items():
        if build["revision"] != revisions[build["arm"]] or key != build["arm"] + "-" + build["sdk"]:
            raise ValueError("build source differs from frozen definition")
        directory = Path(build["directory"])
        sdk_root = directory / "sdk"
        actual_names = {str(p.relative_to(sdk_root)) for prefix in baseline.PATHS
                        for p in (sdk_root / prefix).rglob("*") if p.is_file()}
        if actual_names != set(build["sdk_sources"]["files"]):
            raise ValueError("frozen SDK file inventory changed")
        for name, expected in build["sdk_sources"]["files"].items():
            if baseline.digest(directory / "sdk" / name) != expected:
                raise ValueError("frozen SDK source changed: " + name)
        if baseline.digest(directory / "sdk/Package.swift") != build["package_sha256"]:
            raise ValueError("frozen package changed")


def validate_cell(manifest, key, device, framework, layout, poses):
    if manifest.get("experiment", "EXP-195") == "EXP-195":
        if manifest.get("definition", {}).get("experiment", "EXP-195") != "EXP-195":
            raise ValueError("experiment identity differs from definition")
        return
    if (device == "duo") != poses:
        raise ValueError("Duo cells require all real pose boundaries")
    declared = manifest.get("declared_multiple_scenes", False)
    cells = manifest["definition"]["matrix"]["inventory"]
    matching = [c for c in cells if (c["build"], c["device"], c["framework"], c["layout"], c["multiple_scenes"])
                == (key, device, framework, layout, declared)]
    if len(matching) != 1:
        raise ValueError("cell is outside the fixed matrix")
    if matching[0]["input"] != "EXISTING XCTEST + ACTUAL DEVICE HUB POSES":
        raise ValueError("old-build Duo cell requires prepared human input; failed XCTest path is blocked")
    identity = (key, device, framework, layout)
    if any((r.get("build"), r.get("device"), r.get("framework"), r.get("layout")) == identity
           for r in manifest["runs"] + manifest["failures"]):
        raise ValueError("cell already attempted; no implicit retry")


def prepare(definition_path=None):
    experiment, revisions, definition = configuration(definition_path)
    prefix_name = namespace(experiment)
    attempt = Path(tempfile.mkdtemp(prefix=prefix_name + "-automatic-"))
    manifest = {"experiment": experiment, "created_at": time.time(), "head": call(["git", "rev-parse", "HEAD"]),
                "protected": protected_state(REPO), "definition": definition,
                "fixture": baseline.fingerprint(HERE / "Fixture"), "ui_tests": baseline.fingerprint(HERE / "UITests"),
                "builds": {}, "runs": [], "failures": [], "devices": {}}
    save(attempt / "definition.json", manifest["definition"])
    manifest["definition_sha256"] = hashlib.sha256((attempt / "definition.json").read_bytes()).hexdigest()
    manifest["host_helpers"] = helper_fingerprint()
    for sdk, developer in DEVELOPERS.items():
        env = dict(os.environ, DEVELOPER_DIR=developer)
        version = call(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], env=env)
        if version != sdk: raise RuntimeError(f"expected SDK{sdk}, got {version}")
        for arm, revision in revisions.items():
            key = arm + "-" + sdk
            root = attempt / key; sdk_root = root / "sdk"; sdk_root.mkdir(parents=True)
            archive = subprocess.check_output(["git", "archive", revision, "--", *baseline.PATHS], cwd=REPO)
            with tarfile.open(fileobj=io.BytesIO(archive)) as tar: tar.extractall(sdk_root, filter="data")
            sources = baseline.fingerprint(sdk_root)
            (sdk_root / "Package.swift").write_text(baseline.package())
            shutil.copytree(HERE / "Fixture", root / "Sources")
            shutil.copytree(HERE / "UITests", root / "UITests")
            prefix = "com.datadoghq." + prefix_name + "." + arm + ".sdk" + sdk.replace(".", "")
            targets = {}
            for framework in ["UIKit", "SwiftUI"]:
                target = framework + "Fixture"
                info = {"CFBundleName": target, "CFBundleDisplayName": prefix_name.upper() + " " + framework,
                    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                    "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundlePackageType": "APPL", "UILaunchScreen": {},
                    "LSRequiresIPhoneOS": True, "FixtureFramework": framework,
                    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
                    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}}
                if framework == "UIKit":
                    info["UIApplicationSceneManifest"]["UISceneConfigurations"] = {"UIWindowSceneSessionRoleApplication": [{"UISceneConfigurationName": "Default", "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate"}]}
                with (root / (target + ".plist")).open("wb") as f: plistlib.dump(info, f)
                targets[target] = {"type": "application", "platform": "iOS", "deploymentTarget": "16.0",
                    "sources": ["Sources/Observation.swift", "Sources/" + framework + "App.swift"],
                    "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": prefix + "." + framework.lower(), "SWIFT_VERSION": "5.0",
                        "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": target + ".plist", "CODE_SIGNING_ALLOWED": "NO",
                        "SWIFT_STRICT_CONCURRENCY": "minimal", "SWIFT_OPTIMIZATION_LEVEL": "-O", "TARGETED_DEVICE_FAMILY": "1,2"}},
                    "dependencies": [{"package": "SDK", "product": name} for name in ["DatadogCore", "DatadogRUM"]]}
            targets["CoverageUITests"] = {"type": "bundle.ui-testing", "platform": "iOS", "deploymentTarget": "16.0", "sources": ["UITests"],
                "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": prefix + ".uitests", "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "5.0", "TEST_TARGET_NAME": "UIKitFixture", "CODE_SIGNING_ALLOWED": "NO"}},
                "dependencies": [{"target": "UIKitFixture"}, {"target": "SwiftUIFixture"}]}
            project = {"name": "AutomaticCoverage", "packages": {"SDK": {"path": "sdk"}}, "targets": targets,
                "schemes": {"Coverage": {"build": {"targets": {"UIKitFixture": "all", "SwiftUIFixture": "all", "CoverageUITests": ["test"]}},
                    "test": {"config": "Release", "targets": ["CoverageUITests"]}, "run": {"config": "Release"}}}}
            save(root / "project.json", project)
            call(["xcodegen", "generate", "--spec", "project.json"], cwd=root, log=root / "generate.log")
            manifest["builds"][key] = {"sdk": sdk, "arm": arm, "revision": revision, "directory": str(root), "bundle_prefix": prefix,
                "toolchain": call(["xcodebuild", "-version"], env=env), "sdk_sources": sources,
                "package_sha256": baseline.digest(sdk_root / "Package.swift"), "state": "PREPARED"}
    save(attempt / "manifest.json", manifest)
    print(str(attempt), flush=True)

def build(attempt, key):
    path = attempt / "manifest.json"; m = json.loads(path.read_text()); b = m["builds"][key]; root = Path(b["directory"])
    validate_frozen_inputs(attempt, m)
    if m.get("experiment") != "EXP-195" and b["state"] != "PREPARED":
        raise ValueError("build already attempted; no implicit retry")
    env = dict(os.environ, DEVELOPER_DIR=DEVELOPERS[b["sdk"]])
    command = ["xcodebuild", "build-for-testing", "-project", str(root / "AutomaticCoverage.xcodeproj"), "-scheme", "Coverage",
        "-configuration", "Release", "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(root / "derived"),
        "CODE_SIGNING_ALLOWED=NO", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "-jobs", "4", "-quiet"]
    b["command"] = command; b["state"] = "BUILDING"; save(path, m)
    try:
        call(command, env=env, log=root / "build.log", timeout=900)
        b["apps"] = {}
        for fw in ["UIKit", "SwiftUI"]:
            app = root / "derived/Build/Products/Release-iphonesimulator" / (fw + "Fixture.app")
            info = plistlib.loads((app / "Info.plist").read_bytes())
            b["apps"][fw] = {"path": str(app), "identity": inventory(app), "build_sdk": info.get("DTSDKName"), "deployment": info.get("MinimumOSVersion")}
            if not str(info.get("DTSDKName", "")).endswith(b["sdk"]): raise RuntimeError("built SDK identity mismatch")
        b["runner"] = {"path": str(root / "derived/Build/Products/Release-iphonesimulator/CoverageUITests-Runner.app")}
        b["runner"]["identity"] = inventory(b["runner"]["path"])
        b["xctestrun"] = str(next((root / "derived/Build/Products").glob("*.xctestrun")))
        b["state"] = "BUILT"
    except Exception as e:
        b["state"] = "BUILD_FAILED"; m["failures"].append({"key": key, "stage": "build", "error": str(e), "log": str(root / "build.log")})
        save(path, m); raise
    save(path, m); print(json.dumps({"build": key, "state": b["state"]}), flush=True)

def devices(attempt):
    path = attempt / "manifest.json"; m = json.loads(path.read_text())
    validate_frozen_inputs(attempt, m)
    if m.get("experiment") != "EXP-195" and m["devices"]:
        raise ValueError("task-owned devices already created")
    for label, device_type, runtime in [("regular", "iPhone-17", "iOS-27-0"), ("duo", "iPhone-Duo", "iOS-27-1")]:
        identifier = call(["xcrun", "simctl", "create", namespace(m.get("experiment", "EXP-195")).upper() + " " + label + " " + uuid.uuid4().hex[:6],
            "com.apple.CoreSimulator.SimDeviceType." + device_type, "com.apple.CoreSimulator.SimRuntime." + runtime])
        m["devices"][label] = {"udid": identifier, "owned": True, "runtime": runtime}; save(path, m)
    print(json.dumps(m["devices"]), flush=True)

def read_rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]

def run_cell(attempt, key, device, framework, layout, poses):
    path = attempt / "manifest.json"; m = json.loads(path.read_text()); b = m["builds"][key]
    validate_frozen_inputs(attempt, m)
    validate_cell(m, key, device, framework, layout, poses)
    assert b["state"] == "BUILT"
    collector_key = b["arm"] + "-27.1" if device == "duo" else key
    collector = m["builds"][collector_key]
    assert baseline.fingerprint(Path(b["directory"]) / "Sources") == m["fixture"], "frozen application source drift"
    assert baseline.fingerprint(Path(collector.get("collector_directory", collector["directory"])) / "UITests") == m["ui_tests"], "collector source drift"
    assert inventory(collector["runner"]["path"]) == collector["runner"]["identity"], "frozen runner drift"
    destination = m["devices"][device]["udid"]
    call(["xcrun", "simctl", "boot", destination], check=False)
    call(["xcrun", "simctl", "bootstatus", destination, "-b"], timeout=120)
    run_id = namespace(m.get("experiment", "EXP-195")) + "-" + uuid.uuid4().hex
    directory = attempt / "runs" / run_id; directory.mkdir(parents=True)
    item = {"run_id": run_id, "build": key, "device": device, "udid": destination,
            "framework": framework, "layout": layout, "poses": poses, "directory": str(directory), "state": "STARTED",
            "collector_build_key": collector_key, "runner_bundle": collector["runner"]["identity"]["bundleIdentifier"]}
    item["declared_multiple_scenes"] = m.get("declared_multiple_scenes", False)
    item["built_app_metadata"] = {fw: app_metadata(b["apps"][fw]["path"]) for fw in ["UIKit", "SwiftUI"]}
    assert all(value["declared_multiple_scenes"] is item["declared_multiple_scenes"] for value in item["built_app_metadata"].values()), "wrong frozen scene manifest"
    if "app_metadata" in b:
        assert item["built_app_metadata"] == b["app_metadata"], "frozen app metadata drift"
    item["installed_app_metadata"] = {}
    m["runs"].append(item); save(path, m)
    save(attempt / "active-run.json", item)
    bundles = [b["bundle_prefix"] + "." + fw.lower() for fw in ["UIKit", "SwiftUI"]]
    runner_bundle = item["runner_bundle"]
    for bundle in [*bundles, runner_bundle]:
        call(["xcrun", "simctl", "terminate", destination, bundle], check=False)
        call(["xcrun", "simctl", "uninstall", destination, bundle], check=False)
        p = subprocess.run(["xcrun", "simctl", "get_app_container", destination, bundle, "data"], env=RUN_ENV, capture_output=True)
        if p.returncode == 0: raise RuntimeError("clean uninstall failed")
    item["clean_install"] = True; item["installed"] = {}
    for fw in ["UIKit", "SwiftUI"]:
        app = b["apps"][fw]
        assert inventory(app["path"]) == app["identity"], "frozen binary changed"
        call(["xcrun", "simctl", "install", destination, app["path"]])
        installed = call(["xcrun", "simctl", "get_app_container", destination, app["identity"]["bundleIdentifier"], "app"])
        item["installed"][fw] = inventory(installed)
        assert item["installed"][fw] == app["identity"], "installed code differs"
        item["installed_app_metadata"][fw] = app_metadata(installed)
        assert item["installed_app_metadata"][fw] == item["built_app_metadata"][fw], "installed app metadata differs"
    test_file = Path(collector["xctestrun"])
    spec = plistlib.loads(test_file.read_bytes())
    target = spec["TestConfigurations"][0]["TestTargets"][0] if "TestConfigurations" in spec else spec["CoverageUITests"]
    # Modern XCTest understands Duo displays even when the observed app was
    # genuinely built with an older SDK. Keep app and collector identities separate.
    target["UITargetAppPath"] = b["apps"]["UIKit"]["path"]
    target["DependentProductPaths"] = [
        b["apps"]["UIKit"]["path"] if value.endswith("/UIKitFixture.app") else
        b["apps"]["SwiftUI"]["path"] if value.endswith("/SwiftUIFixture.app") else value
        for value in target.get("DependentProductPaths", [])
    ]
    target["BundleIdentifiersForCrashReportEmphasis"] = [*bundles, runner_bundle]
    target["EnvironmentVariables"] = {**target.get("EnvironmentVariables", {}), "EXP195_RUN_ID": run_id,
        "EXP195_BUNDLE_PREFIX": b["bundle_prefix"], "EXP195_DUO_PHASES": "1" if poses else "0"}
    # Keep __TESTROOT__ resolution at the original products directory.
    run_spec = test_file.parent / (run_id + ".xctestrun")
    with run_spec.open("wb") as f: plistlib.dump(spec, f)
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(run_spec), "-destination", "platform=iOS Simulator,id=" + destination,
        "-only-testing:CoverageUITests/AutomaticCoverageUITests/test" + framework + layout.capitalize(),
        "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1", "-resultBundlePath", str(directory / "result.xcresult"), "-quiet"]
    item["command"] = command; save(path, m)
    save(attempt / "active-run.json", item)
    print(json.dumps({"run_id": run_id, "cell": [key, device, framework, layout], "directory": str(directory)}), flush=True)
    with (directory / "test.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=RUN_ENV, start_new_session=True)
        try: code = process.wait(timeout=950 if poses else 220)
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=10)
            code = -1
    item["test_exit"] = code
    bundle = b["bundle_prefix"] + "." + framework.lower()
    container = call(["xcrun", "simctl", "get_app_container", destination, bundle, "data"], check=False)
    native = Path(container) / "Documents/events.jsonl"
    if native.exists(): shutil.copyfile(native, directory / "events.jsonl")
    runner = call(["xcrun", "simctl", "get_app_container", destination, runner_bundle, "data"], check=False)
    receipt_path = Path(runner) / "Documents" / run_id / "receipts.json"
    if receipt_path.exists(): shutil.copyfile(receipt_path, directory / "receipts.json")
    runner_app = call(["xcrun", "simctl", "get_app_container", destination, runner_bundle, "app"], check=False)
    if runner_app:
        item["installed_runner"] = inventory(runner_app)
        assert item["installed_runner"] == collector["runner"]["identity"], "installed test runner differs"
    if (directory / "result.xcresult").exists():
        call(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(directory / "result.xcresult")], log=directory / "test-summary.json", check=False)
    item["installed_after_test"] = {}
    item["app_metadata_after_test"] = {}
    for fw in ["UIKit", "SwiftUI"]:
        installed_app = call(["xcrun", "simctl", "get_app_container", destination, b["apps"][fw]["identity"]["bundleIdentifier"], "app"])
        item["installed_after_test"][fw] = inventory(installed_app)
        assert item["installed_after_test"][fw] == b["apps"][fw]["identity"], "test execution replaced an observed app"
        item["app_metadata_after_test"][fw] = app_metadata(installed_app)
        assert item["app_metadata_after_test"][fw] == item["built_app_metadata"][fw], "test execution changed app metadata"
    item["state"] = "COLLECTED" if code == 0 and (directory / "events.jsonl").exists() and (directory / "receipts.json").exists() else "INPUT_OR_FIXTURE_FAILED"
    for name in [*bundles, runner_bundle]:
        call(["xcrun", "simctl", "terminate", destination, name], check=False)
        call(["xcrun", "simctl", "uninstall", destination, name], check=False)
        p = subprocess.run(["xcrun", "simctl", "get_app_container", destination, name, "data"], env=RUN_ENV, capture_output=True)
        if p.returncode == 0: raise RuntimeError("cleanup failed")
    item["cleanup"] = True
    assert protected_state(REPO) == m["protected"], "protected paths changed"
    save(path, m); save(directory / "run.json", item)
    print(json.dumps({"run_id": run_id, "state": item["state"], "test_exit": code}), flush=True)

def main():
    p = argparse.ArgumentParser(); p.add_argument("stage", choices=["prepare", "build", "devices", "run"])
    p.add_argument("--definition", type=Path); p.add_argument("--attempt", type=Path);p.add_argument("--build");p.add_argument("--device", choices=["regular", "duo"])
    p.add_argument("--framework", choices=["UIKit", "SwiftUI"]);p.add_argument("--layout", choices=["stack", "split"]);p.add_argument("--poses", action="store_true")
    a = p.parse_args()
    if a.stage == "prepare": prepare(a.definition)
    elif a.stage == "build": build(a.attempt, a.build)
    elif a.stage == "devices": devices(a.attempt)
    else:
        current = json.loads((a.attempt / "manifest.json").read_text())
        validate_frozen_inputs(a.attempt, current)
        validate_cell(current, a.build, a.device, a.framework, a.layout, a.poses)
        try:
            run_cell(a.attempt, a.build, a.device, a.framework, a.layout, a.poses)
        except Exception as error:
            path = a.attempt / "manifest.json"; m = json.loads(path.read_text())
            b = m["builds"][a.build]; destination = m["devices"][a.device]["udid"]
            collector_key = b["arm"] + "-27.1" if a.device == "duo" else a.build
            bundles = [b["bundle_prefix"] + "." + suffix for suffix in ["uikit", "swiftui"]]
            bundles.append(m["builds"][collector_key]["runner"]["identity"]["bundleIdentifier"])
            for bundle in bundles:
                call(["xcrun", "simctl", "terminate", destination, bundle], check=False)
                call(["xcrun", "simctl", "uninstall", destination, bundle], check=False)
                result = subprocess.run(["xcrun", "simctl", "get_app_container", destination, bundle, "data"], env=RUN_ENV, capture_output=True)
                if result.returncode == 0: raise RuntimeError("exception cleanup failed") from error
            m["failures"].append({"stage": "run preparation/collection", "build": a.build, "device": a.device,
                "framework": a.framework, "layout": a.layout, "error": str(error), "cleanup": True})
            save(path, m)
            raise
if __name__ == "__main__": main()
