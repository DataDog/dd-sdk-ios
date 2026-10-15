#!/usr/bin/env python3
"""Isolated EXP-160 baseline. No local xcconfig or main Xcode project is accessed."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
REVISIONS = {"baseline": "92f021ba7e4a866f84a52da93ed8b63f3dc75882", "candidate": "af63657f08dbecb66e7c3ae97ed53fc8f7b065b9"}
ENV = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode_27.app/Contents/Developer")
PATHS = ["DatadogCore/Sources", "DatadogCore/Private", "DatadogCore/Resources", "DatadogInternal/Sources", "DatadogRUM/Sources", "DatadogRUM/Private", "DatadogRUM/Resources"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(root):
    files = {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob("*")) if p.is_file()}
    return {"file_count": len(files), "sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(), "files": files}


def call(command, *, cwd=None, log=None, check=True):
    if log:
        with open(log, "w") as output:
            result = subprocess.run(command, cwd=cwd, env=ENV, stdout=output, stderr=subprocess.STDOUT)
        text = ""
    else:
        result = subprocess.run(command, cwd=cwd, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        text = result.stdout
    if check and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}; log={log}; {getattr(result, 'stderr', '')}")
    return text


def package():
    return '''// swift-tools-version: 6.0
import PackageDescription
let checked: [SwiftSetting] = [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-testing"])]
let package = Package(name: "DatadogBaseline", platforms: [.iOS(.v15)], products: [
.library(name: "DatadogCore", targets: ["DatadogCore"]),
.library(name: "DatadogRUM", targets: ["DatadogRUM"]),
.library(name: "DatadogInternal", targets: ["DatadogInternal"])
], targets: [
.target(name: "DatadogInternal", path: "DatadogInternal/Sources", swiftSettings: checked),
.target(name: "DatadogPrivate", path: "DatadogCore/Private"),
.target(name: "DatadogRUMPrivate", path: "DatadogRUM/Private"),
.target(name: "DatadogCore", dependencies: ["DatadogInternal", "DatadogPrivate"], path: "DatadogCore", sources: ["Sources"], resources: [.copy("Resources/PrivacyInfo.xcprivacy")], swiftSettings: [.define("SPM_BUILD")] + checked),
.target(name: "DatadogRUM", dependencies: ["DatadogInternal", "DatadogRUMPrivate"], path: "DatadogRUM", sources: ["Sources"], resources: [.copy("Resources/PrivacyInfo.xcprivacy")], swiftSettings: [.define("SPM_BUILD")] + checked)
])
'''


def prepare(attempt):
    attempt.mkdir(parents=True, exist_ok=False)
    protocol = (REPO / "DatadogRUM/MultiSceneSupport/BASELINES.md").read_text().split("## Results")[0]
    manifest = {"experiment": "EXP-160", "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "revisions": REVISIONS, "definition_sha256": hashlib.sha256(protocol.encode()).hexdigest(), "fixture": fingerprint(HERE / "Fixture"), "arms": {}, "commands": [], "builds": {}, "runs": [], "invalid_attempts": []}
    manifest["xcode"] = call(["xcodebuild", "-version"]).strip()
    for arm, revision in REVISIONS.items():
        directory = attempt / arm
        sdk = directory / "sdk"
        sdk.mkdir(parents=True)
        archive = subprocess.check_output(["git", "archive", revision, "--", *PATHS], cwd=REPO)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(sdk, filter="data")
        manifest["arms"][arm] = {"sdk_sources": fingerprint(sdk)}
        (sdk / "Package.swift").write_text(package())
        shutil.copytree(HERE / "Fixture", directory / "Sources")
        targets = {}
        for lifecycle in ["Scene", "Legacy"]:
            target = "Fixture" + lifecycle
            info = {"CFBundleName": target, "CFBundleDisplayName": "EXP160 " + lifecycle, "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundlePackageType": "APPL", "UILaunchScreen": {}, "LSRequiresIPhoneOS": True}
            if lifecycle == "Scene":
                info["UIApplicationSceneManifest"] = {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{"UISceneConfigurationName": "Default", "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate"}]}}
            with open(directory / (target + ".plist"), "wb") as output:
                plistlib.dump(info, output)
            targets[target] = {"type": "application", "platform": "iOS", "deploymentTarget": "15.0", "sources": ["Sources"], "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "com.datadoghq.exp160." + arm + "." + lifecycle.lower(), "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "15.0", "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": target + ".plist", "SWIFT_OBJC_BRIDGING_HEADER": "Sources/AllocationCounter.h", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "CANDIDATE" if arm == "candidate" else "", "CODE_SIGNING_ALLOWED": "NO", "ENABLE_TESTABILITY": "YES", "SWIFT_STRICT_CONCURRENCY": "minimal", "SWIFT_OPTIMIZATION_LEVEL": "-O", "TARGETED_DEVICE_FAMILY": "1,2"}}, "dependencies": [{"package": "SDK", "product": name} for name in ["DatadogCore", "DatadogRUM", "DatadogInternal"]]}
        spec = {"name": "EXP160", "packages": {"SDK": {"path": "sdk"}}, "targets": targets, "schemes": {"EXP160": {"build": {"targets": {key: "all" for key in targets}}, "run": {"config": "Release"}}}}
        (directory / "project.json").write_text(json.dumps(spec, indent=2))
        call(["xcodegen", "generate", "--spec", "project.json"], cwd=directory, log=directory / "generate.log")
    save(attempt, manifest)
    return manifest


def save(attempt, manifest):
    (attempt / "manifest.json").write_text(json.dumps(manifest, indent=2))


def build(attempt, manifest, arm):
    directory = attempt / arm
    command = ["xcodebuild", "build", "-project", str(directory / "EXP160.xcodeproj"), "-scheme", "EXP160", "-configuration", "Release", "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(directory / "derived"), "CODE_SIGNING_ALLOWED=NO"]
    manifest["commands"].append(command)
    try:
        call(command, log=directory / "build.log")
    except RuntimeError:
        manifest["invalid_attempts"].append({"stage": "build", "arm": arm, "log": str(directory / "build.log")})
        save(attempt, manifest)
        raise
    manifest["builds"][arm] = {}
    for lifecycle in ["Scene", "Legacy"]:
        app = directory / "derived/Build/Products/Release-iphonesimulator" / ("Fixture" + lifecycle + ".app")
        binary = app / ("Fixture" + lifecycle)
        manifest["builds"][arm][lifecycle] = {"app": str(app), "sha256": digest(binary), "uuid": call(["dwarfdump", "--uuid", str(binary)]).strip(), "deployment_target": "15.0"}
    save(attempt, manifest)


def choose_devices():
    available = json.loads(call(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
    result = {}
    for version, runtime in [("27.0", "com.apple.CoreSimulator.SimRuntime.iOS-27-0"), ("26.5", "com.apple.CoreSimulator.SimRuntime.iOS-26-5")]:
        devices = [d for d in available.get(runtime, []) if d["name"].startswith("iPhone")]
        devices.sort(key=lambda d: (d["state"] != "Booted", d["name"]))
        if not devices:
            raise RuntimeError("Required runtime unavailable: " + version)
        device = devices[0]
        if device["state"] != "Booted":
            call(["xcrun", "simctl", "boot", device["udid"]])
            call(["xcrun", "simctl", "bootstatus", device["udid"], "-b"])
        result[version] = {key: device[key] for key in ["udid", "name", "state"]}
    return result


def run_one(attempt, manifest, arm, lifecycle, version, mode, order, driver=None):
    destination = manifest["devices"][version]["udid"]
    app = manifest["builds"][arm][lifecycle]["app"]
    binary = Path(app) / ("Fixture" + lifecycle)
    if digest(binary) != manifest["builds"][arm][lifecycle]["sha256"]:
        raise RuntimeError("Frozen binary changed before launch")
    bundle = "com.datadoghq.exp160." + arm + "." + lifecycle.lower()
    run_id = "exp160-" + uuid.uuid4().hex
    directory = attempt / "runs" / run_id
    directory.mkdir(parents=True)
    call(["xcrun", "simctl", "terminate", destination, bundle], check=False)
    call(["xcrun", "simctl", "uninstall", destination, bundle], check=False)
    absent = subprocess.run(["xcrun", "simctl", "get_app_container", destination, bundle, "data"], env=ENV, capture_output=True).returncode != 0
    if not absent:
        raise RuntimeError("Clean uninstall not proven")
    call(["xcrun", "simctl", "install", destination, app])
    launch = ["xcrun", "simctl", "launch", "--console", destination, bundle, "--mode", mode, "--run-id", run_id]
    manifest["commands"].append(launch)
    stdout = open(directory / "stdout.log", "w")
    stderr = open(directory / "stderr.log", "w")
    process = subprocess.Popen(launch, env=ENV, stdout=stdout, stderr=stderr)
    launched = "console process " + str(process.pid)
    container = Path(call(["xcrun", "simctl", "get_app_container", destination, bundle, "data"]).strip())
    output = container / "Documents/result.json"
    if driver:
        driver(container, destination, bundle)
    deadline = time.monotonic() + 65
    while not output.exists() and time.monotonic() < deadline and process.poll() is None:
        time.sleep(0.25)
    if not output.exists():
        item = {"run_id": run_id, "arm": arm, "lifecycle": lifecycle, "os": version, "mode": mode, "status": "INCONCLUSIVE", "reason": "Process exited without terminal fixture result" if process.poll() is not None else "No terminal fixture result before deadline", "process_exit_code": process.poll(), "artifact": str(directory)}
    else:
        shutil.copyfile(output, directory / "result.json")
        data = json.loads(output.read_text())
        if data.get("run_id") != run_id:
            raise RuntimeError("Stale fixture run identifier")
        item = {"run_id": run_id, "arm": arm, "lifecycle": lifecycle, "os": version, "mode": mode, "order": order, "clean_install": absent, "status": "MEASURED", "result": data, "artifact": str(directory / "result.json"), "launch": launched.strip()}
    call(["xcrun", "simctl", "terminate", destination, bundle], check=False)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=5)
    stdout.close(); stderr.close()
    item["binary_sha256"] = manifest["builds"][arm][lifecycle]["sha256"]
    item["fixture_sha256"] = manifest["builds"][arm][lifecycle].get("fixture", manifest["fixture"])["sha256"]
    manifest["runs"].append(item)
    save(attempt, manifest)
    print(json.dumps({key: item[key] for key in ["arm", "lifecycle", "os", "mode", "status"]}), flush=True)


def verify(attempt, manifest):
    protocol = (REPO / "DatadogRUM/MultiSceneSupport/BASELINES.md").read_text().split("## Results")[0]
    checks = {"verified_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "definition_unchanged": hashlib.sha256(protocol.encode()).hexdigest() == manifest["definition_sha256"],
              "fixture_unchanged": fingerprint(HERE / "Fixture") == manifest["fixture"], "arms": {}, "builds": {}}
    checks["host"] = {"system": call(["sw_vers"]).strip(), "architecture": call(["uname", "-m"]).strip(),
                      "model": call(["sysctl", "-n", "hw.model"]).strip(), "cpu": call(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()}
    for arm, data in manifest["arms"].items():
        expected = data["sdk_sources"]["files"]
        actual = {path: digest(attempt / arm / "sdk" / path) for path in expected}
        checks["arms"][arm] = {"original_sdk_files_unchanged": actual == expected,
                                "copied_fixture_unchanged": fingerprint(attempt / arm / "Sources") == manifest["fixture"],
                                "package_manifest_sha256": digest(attempt / arm / "sdk/Package.swift")}
        checks["builds"][arm] = {}
        for lifecycle, build in manifest["builds"][arm].items():
            binary = Path(build["app"]) / ("Fixture" + lifecycle)
            checks["builds"][arm][lifecycle] = {"unchanged": digest(binary) == build["sha256"],
                                              "mach_o_build_version": call(["vtool", "-show-build", str(binary)]).strip()}
    checks["runtime_inventory"] = [{k: item.get(k) for k in ["name", "version", "buildversion", "identifier", "isAvailable"]} for item in json.loads(call(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"] if "iOS" in item.get("name", "")]
    crash_evidence = []
    for path in sorted(Path.home().joinpath("Library/Logs/DiagnosticReports").glob("FixtureLegacy-*.ips")):
        lines = path.read_text().splitlines()
        try:
            header, body = json.loads(lines[0]), json.loads("\n".join(lines[1:]))
        except (ValueError, IndexError):
            continue
        arm = next((a for a in REVISIONS if header.get("bundleID") == "com.datadoghq.exp160." + a + ".legacy" and header.get("slice_uuid", "").upper() in manifest["builds"][a]["Legacy"]["uuid"].upper()), None)
        if arm:
            crash_evidence.append({"file": path.name, "arm": arm, "binary_uuid": header.get("slice_uuid"), "exception_type": body.get("exception", {}).get("type"), "signal": body.get("exception", {}).get("signal"), "triggered_symbols": [f.get("symbol", "<no symbol>") for t in body.get("threads", []) if t.get("triggered") for f in t.get("frames", [])[:8]]})
    checks["legacy_platform_crash_evidence"] = crash_evidence
    checks["passed"] = checks["definition_unchanged"] and checks["fixture_unchanged"] and all(
        data["original_sdk_files_unchanged"] and data["copied_fixture_unchanged"] for data in checks["arms"].values()) and all(
        data["unchanged"] for builds in checks["builds"].values() for data in builds.values())
    checks["scope"] = "Post-run verification. Original runs bind to frozen build table; later variants additionally store per-launch identity."
    manifest["verification"] = checks
    save(attempt, manifest)
    if not checks["passed"]:
        raise RuntimeError("Frozen source/fixture/build identity changed")
    return checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["prepare", "build", "run", "verify", "all"])
    parser.add_argument("--attempt", type=Path)
    parser.add_argument("--output", type=Path, help="Durable result destination; all defaults to ATTEMPT/summary.json")
    parser.add_argument("--arm", choices=list(REVISIONS))
    parser.add_argument("--workload", choices=["all", "compatibility", "performance"], default="all")
    args = parser.parse_args()
    attempt = args.attempt or Path(tempfile.gettempdir()) / ("exp160-" + uuid.uuid4().hex[:12])
    manifest = prepare(attempt) if args.stage in ["prepare", "all"] else json.loads((attempt / "manifest.json").read_text())
    print(str(attempt), flush=True)
    if args.stage in ["build", "all"]:
        for arm in ([args.arm] if args.arm else REVISIONS):
            build(attempt, manifest, arm)
    if args.stage in ["run", "all"]:
        manifest["devices"] = choose_devices()
        for version in manifest["devices"]:
            for lifecycle in ["Scene", "Legacy"]:
                for mode in ["automatic", "manual"]:
                    for arm in REVISIONS:
                        if args.workload != "performance":
                            run_one(attempt, manifest, arm, lifecycle, version, mode, "compatibility")
            for mode in ["disabled", "dispatch", "internal"]:
                for index, arm in enumerate(["baseline", "candidate", "candidate", "baseline"]):
                    if args.workload != "compatibility":
                        run_one(attempt, manifest, arm, "Scene", version, mode, index)
    if args.stage == "all" and args.workload == "all":
        import lifecycle
        import focused
        lifecycle.prepare(attempt, manifest)
        lifecycle.run_matrix(attempt, manifest)
        focused.prepare(attempt, manifest)
        focused.run_matrix(attempt, manifest)
    if args.stage in ["verify", "all"]:
        verify(attempt, manifest)
    save(attempt, manifest)
    if args.output or args.stage == "all":
        import analyze
        analyze.write_results(attempt, args.output or attempt / "summary.json")


if __name__ == "__main__":
    main()
