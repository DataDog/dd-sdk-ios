#!/usr/bin/env python3
"""EXP-166 repair measurement using the frozen EXP-160 dispatch workload."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("baseline_runner", HERE.parent / "baselines/run.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)


def prepare():
    attempt = Path(tempfile.gettempdir()) / ("exp166-" + uuid.uuid4().hex[:12])
    head = base.call(["git", "rev-parse", "HEAD"], cwd=base.REPO).strip()
    base.REVISIONS = dict(base.REVISIONS, candidate=head)
    manifest = base.prepare(attempt)
    manifest["experiment"] = "EXP-166"
    manifest["original_fixture"] = manifest["fixture"]
    # Only the explicitly listed SDK directories are copied; project and local
    # configuration are never opened. This freezes the uncommitted candidate.
    sdk = attempt / "candidate/sdk"
    for relative in base.PATHS:
        target = sdk / relative
        shutil.rmtree(target)
        shutil.copytree(base.REPO / relative, target)
    patch = base.call(["git", "diff", "HEAD", "--", *base.PATHS], cwd=base.REPO)
    (attempt / "candidate.patch").write_text(patch)
    manifest["candidate_patch_sha256"] = hashlib.sha256(patch.encode()).hexdigest()
    manifest["arms"]["candidate"]["sdk_sources"] = {
        "files": {str(p.relative_to(sdk)): base.digest(p)
                  for relative in base.PATHS for p in sorted((sdk / relative).rglob("*")) if p.is_file()}
    }
    files = manifest["arms"]["candidate"]["sdk_sources"]["files"]
    manifest["arms"]["candidate"]["sdk_sources"].update(
        file_count=len(files), sha256=hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest())
    manifest["fixture_adaptation"] = "Only owner arguments and scoped SPI lookup names change in the copied fixture; workloads and thresholds are unchanged."
    for arm in base.REVISIONS:
        source = attempt / arm / "Sources/InternalFixture.swift"
        text = source.read_text()
        text = text.replace("RUMContextHandoff.current?", "RUMContextHandoff.current(for: monitorSubscriber?.rumContextHandoffOwner)?")
        text = text.replace("RUMContextHandoff.current !=", "RUMContextHandoff.current(for: monitorSubscriber?.rumContextHandoffOwner) !=")
        text = text.replace("RUMUIEventNetworkContext.currentSceneIdentifier", "RUMUIEventNetworkContext.currentSceneIdentifier(for: monitorSubscriber?.rumContextHandoffOwner)")
        text = text.replace("RUMContextHandoff.withValue(rumContext:", "RUMContextHandoff.withValue(owner: monitorSubscriber?.rumContextHandoffOwner, rumContext:")
        source.write_text(text)
    manifest["fixture"] = base.fingerprint(attempt / "candidate/Sources")
    assert base.fingerprint(attempt / "baseline/Sources") == manifest["fixture"]
    base.save(attempt, manifest)
    return attempt, manifest



def focused_build(attempt, manifest):
    directory = attempt / "candidate"
    sources = directory / "FocusedSources"
    shutil.copytree(directory / "Sources", sources)
    focused = (base.HERE / "FocusedChecks.swift").read_text()
    focused = focused.replace("let expectedScene =", "let owner = (RUMMonitor.shared() as? RUMCommandSubscriber)?.rumContextHandoffOwner\n        let expectedScene =")
    focused = focused.replace("RUMContextHandoff.current", "RUMContextHandoff.current(for: owner)")
    focused = focused.replace("RUMContextHandoff.withValue(rumContext:", "RUMContextHandoff.withValue(owner: owner, rumContext:")
    (sources / "FocusedChecks.swift").write_text(focused)
    app = sources / "App.swift"
    text = app.read_text().replace('if mode == "internal" {', 'if mode == "focused" {')
    text = text.replace('result["internal"] = InternalFixture.run(window: window!)', 'result["focused"] = FocusedChecks.run(window: window!)')
    app.write_text(text)
    project = json.loads((directory / "project.json").read_text())
    target = json.loads(json.dumps(project["targets"]["FixtureScene"]))
    target["sources"] = ["FocusedSources"]
    target["settings"]["base"]["SWIFT_OBJC_BRIDGING_HEADER"] = "FocusedSources/AllocationCounter.h"
    target["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"] = "com.datadoghq.exp160.candidate.focused"
    project["targets"]["FixtureFocused"] = target
    project["schemes"]["EXP166Focused"] = {"build": {"targets": {"FixtureFocused": "all"}}}
    (directory / "project.json").write_text(json.dumps(project, indent=2))
    base.call(["xcodegen", "generate", "--spec", "project.json"], cwd=directory, log=directory / "generate-focused.log")
    command = ["xcodebuild", "build", "-project", str(directory / "EXP160.xcodeproj"), "-scheme", "EXP166Focused", "-configuration", "Release", "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(directory / "derived"), "CODE_SIGNING_ALLOWED=NO"]
    manifest["commands"].append(command)
    base.call(command, log=directory / "build-focused.log")
    app = directory / "derived/Build/Products/Release-iphonesimulator/FixtureFocused.app"
    manifest["builds"]["candidate"]["Focused"] = {
        "app": str(app), "sha256": base.digest(app / "FixtureFocused"),
        "uuid": base.call(["dwarfdump", "--uuid", str(app / "FixtureFocused")]).strip(),
        "fixture": base.fingerprint(sources), "deployment_target": "15.0"}
    base.save(attempt, manifest)


def report(attempt, manifest):
    spec = importlib.util.spec_from_file_location("baseline_analyzer", base.HERE / "analyze.py")
    analyzer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analyzer)
    acceptance = dict(manifest, runs=[r for r in manifest["runs"] if r.get("order") != "diagnostic-only"])
    result = analyzer.analyze(acceptance)
    summary = {key: result[key] for key in ["experiment", "created_at", "revisions", "definition_sha256", "fixture", "xcode", "builds", "devices", "verification", "performance", "reentrancy", "custom_nop", "limitations"]}
    summary["gates"] = {key: result["gates"][key] for key in ["P01", "P02", "P04"]}
    summary["candidate_patch_sha256"] = manifest["candidate_patch_sha256"]
    summary["original_fixture"] = manifest["original_fixture"]
    summary["fixture_adaptation"] = manifest["fixture_adaptation"]
    summary["sources"] = {}
    for arm, value in manifest["arms"].items():
        files = value["sdk_sources"]["files"]
        summary["sources"][arm] = {"file_count": len(files), "sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}
    summary["commands"] = manifest["commands"]
    summary["scope"] = "EXP-166 dispatch repair only; no other compatibility or retention gate is reassessed."
    summary["samples_sha256"] = base.digest(attempt / "manifest.json")
    (attempt / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({"gates": summary["gates"], "summary": str(attempt / "summary.json")}), flush=True)


def verify(attempt, manifest):
    original = base.fingerprint(base.HERE / "Fixture")
    protocol = (base.REPO / "DatadogRUM/MultiSceneSupport/BASELINES.md").read_text().split("## Results")[0]
    checks = {"original_fixture_unchanged": original == manifest["original_fixture"],
              "definition_unchanged": hashlib.sha256(protocol.encode()).hexdigest() == manifest["definition_sha256"],
              "arms": {}, "builds": {}, "focused_fixtures": {}}
    for arm, data in manifest["arms"].items():
        expected = data["sdk_sources"]["files"]
        checks["arms"][arm] = {
            "sdk_unchanged": all(base.digest(attempt / arm / "sdk" / path) == digest for path, digest in expected.items()),
            "fixture_unchanged": base.fingerprint(attempt / arm / "Sources") == manifest["fixture"]}
    for arm, builds in manifest["builds"].items():
        checks["builds"][arm] = {
            name: base.digest(Path(build["app"]) / ("Fixture" + name)) == build["sha256"]
            for name, build in builds.items()}
    for arm, builds in manifest["builds"].items():
        if "Focused" in builds:
            checks["focused_fixtures"][arm] = base.fingerprint(attempt / arm / "FocusedSources") == builds["Focused"]["fixture"]
    checks["passed"] = checks["original_fixture_unchanged"] and checks["definition_unchanged"] and all(
        all(values.values()) for values in checks["arms"].values()) and all(
        all(values.values()) for values in checks["builds"].values()) and all(checks["focused_fixtures"].values())
    manifest["verification"] = checks
    base.save(attempt, manifest)
    if not checks["passed"]:
        raise RuntimeError("Frozen identity changed")
    return checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["prepare", "build", "probe", "run", "focused-build", "focused-run", "verify", "report"])
    parser.add_argument("--attempt", type=Path)
    parser.add_argument("--arm", choices=["baseline", "candidate"])
    args = parser.parse_args()
    if args.stage == "prepare":
        attempt, manifest = prepare()
    else:
        if not args.attempt:
            parser.error("--attempt is required after prepare")
        attempt = args.attempt
        manifest = json.loads((attempt / "manifest.json").read_text())
    print(attempt, flush=True)
    if args.stage == "build":
        for arm in ([args.arm] if args.arm else ["baseline", "candidate"]):
            base.build(attempt, manifest, arm)
    if args.stage == "focused-build":
        focused_build(attempt, manifest)
    if args.stage == "focused-run":
        for version in manifest["devices"]:
            base.run_one(attempt, manifest, "candidate", "Focused", version, "focused", "full-context-P04")
    if args.stage in ["probe", "run"]:
        manifest["devices"] = base.choose_devices()
        if args.stage == "probe":
            base.run_one(attempt, manifest, "candidate", "Scene", "27.0", "internal", "diagnostic-only")
        else:
            for version in manifest["devices"]:
                for mode in ["disabled", "dispatch", "internal"]:
                    for index, arm in enumerate(["baseline", "candidate", "candidate", "baseline"]):
                        base.run_one(attempt, manifest, arm, "Scene", version, mode, index)
    if args.stage in ["probe", "run", "focused-run", "verify", "report"]:
        print(json.dumps(verify(attempt, manifest)), flush=True)
    base.save(attempt, manifest)
    if args.stage == "report":
        report(attempt, manifest)


if __name__ == "__main__":
    main()
