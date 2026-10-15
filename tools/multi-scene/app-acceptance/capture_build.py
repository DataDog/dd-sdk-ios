"""Freeze separate F08 app copies and reuse the accepted build qualification."""
from pathlib import Path
import argparse
import copy
import shlex
import datetime
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    with Path(path).open("x") as output:
        json.dump(value, output, indent=2)
        output.write("\n")


def git(path, *args):
    return subprocess.check_output(["git", "-c", "color.ui=false", *args], cwd=path, text=True).strip()


def project_membership(app):
    project = app / "DatadogApp.xcodeproj/project.pbxproj"
    data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
    objects = data["objects"]
    paths = {}

    def walk(key, parent):
        node = objects[key]
        tree = node.get("sourceTree", "<group>")
        base = app if tree == "SOURCE_ROOT" else (Path("/") if tree == "<absolute>" else parent)
        current = (base / node.get("path", "")).resolve()
        paths[key] = current
        for child in node.get("children", []):
            walk(child, current)

    walk(objects[data["rootObject"]]["mainGroup"], app)
    result = {}
    for target in objects.values():
        if target.get("isa") != "PBXNativeTarget":
            continue
        selected = []
        for identifier in target["buildPhases"]:
            phase = objects[identifier]
            if phase["isa"] == "PBXSourcesBuildPhase":
                selected.extend(str(paths[objects[item]["fileRef"]].relative_to(app)) for item in phase["files"])
        assert len(selected) == len(set(selected)), (target["name"], "duplicate source")
        result[target["name"]] = sorted(selected)
    return result



def project_graph(original, captured):
    """Allow the exact new source and Xcode's observed serialization changes."""
    before = copy.deepcopy(original)
    after = copy.deepcopy(captured)
    old, new = before["objects"], after["objects"]
    additions = set(new) - set(old)
    assert len(additions) == 2 and set(old) <= set(new), "Unexpected project object changes"
    references = [key for key in additions if new[key] == {"isa": "PBXFileReference", "path": "ReleaseValidationCapture.swift", "lastKnownFileType": "sourcecode.swift", "sourceTree": "<group>"}]
    assert len(references) == 1, "Unexpected capture file reference"
    reference = references[0]
    build_files = [key for key in additions if new[key] == {"isa": "PBXBuildFile", "fileRef": reference}]
    assert len(build_files) == 1, "Unexpected capture build reference"
    build_file = build_files[0]
    owners = []
    groups = []
    for key, node in new.items():
        if node.get("isa") == "PBXGroup" and reference in node.get("children", []):
            assert node["children"].count(reference) == 1
            node["children"].remove(reference)
            groups.append(key)
        if node.get("isa") == "PBXSourcesBuildPhase" and build_file in node["files"]:
            assert node["files"].count(build_file) == 1
            node["files"].remove(build_file)
            owners.append(key)
    assert len(groups) == len(owners) == 1
    target = next(node for node in old.values() if node.get("isa") == "PBXNativeTarget" and node["name"] == "DatadogObservability")
    assert owners[0] in target["buildPhases"], "Capture has foreign target membership"
    assert old[groups[0]].get("path") == "DatadogObservability", "Capture has foreign source group"
    uses = {}
    for node in old.values():
        if node.get("isa", "").endswith("BuildPhase"):
            for key in node.get("files", []):
                file_ref = old[key].get("fileRef")
                if file_ref:
                    uses.setdefault(file_ref, set()).add(node["isa"])
    counts = {"flag_serializations": 0, "resource_types": 0}
    for key, node in old.items():
        if node.get("isa") == "XCBuildConfiguration":
            for setting in ("OTHER_SWIFT_FLAGS", "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "OTHER_LDFLAGS"):
                value = node["buildSettings"].get(setting)
                changed = new[key]["buildSettings"].get(setting)
                if value == changed:
                    continue
                assert {type(value), type(changed)} == {list, str}, "Unexpected flag shape"
                def tokens(item):
                    return shlex.split(" ".join(item) if isinstance(item, list) else item)
                assert tokens(value) == tokens(changed), "Compiler/link flag tokens changed"
                new[key]["buildSettings"][setting] = value
                counts["flag_serializations"] += 1
        elif node.get("isa") == "PBXFileReference" and "lastKnownFileType" not in node and "lastKnownFileType" in new[key]:
            suffix = Path(node.get("path", "")).suffix
            assert suffix in {".caf", ".ts"} and uses.get(key) == {"PBXResourcesBuildPhase"}, "Unqualified file type change"
            assert new[key]["lastKnownFileType"] == {".caf": "file", ".ts": "sourcecode.typescript"}[suffix]
            del new[key]["lastKnownFileType"]
            counts["resource_types"] += 1
    for key in additions:
        del new[key]
    assert before["objectVersion"] == "55" and after["objectVersion"] == "56", "Unqualified project format change"
    after["objectVersion"] = before["objectVersion"]
    counts["object_version_55_to_56"] = 1
    assert before == after, "Project dependency, phase, resource, configuration or other graph changed"
    return dict(status="PASS", **counts)


def read_project(app):
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(app / "DatadogApp.xcodeproj/project.pbxproj")]))


def generated_files(root):
    paths = list(root.rglob("*"))
    assert paths and not any(path.is_symlink() for path in paths), "Unexpected generated input symlink"
    return {str(path.relative_to(root)): sha(path) for path in sorted(paths) if path.is_file()}


def relocated_inputs(original_app, app, *, apply=False):
    """Permit only the accepted app-root substitution in generated umbrella paths."""
    original_app, app = original_app.resolve(strict=True), app.resolve(strict=True)
    assert original_app != app
    original = original_app / "Tuist/.build/tuist-derived"
    copied = app / "Tuist/.build/tuist-derived"
    before, actual = generated_files(original), generated_files(copied)
    assert set(before) == set(actual), "Generated compiler-input set changed"
    old_prefix, new_prefix = (str(path).encode() + b"/" for path in (original_app, app))
    maps, expected, changes = {}, {}, {}
    checkout = (app / "Tuist/.build/checkouts").resolve(strict=True)
    for name in sorted(before):
        raw = (original / name).read_bytes()
        corrected = raw
        if name.endswith(".modulemap"):
            count = raw.count(old_prefix)
            assert count > 0, "Module map does not have the qualified absolute root"
            corrected = raw.replace(old_prefix, new_prefix)
            quoted = [line for line in corrected.decode().splitlines() if '"' in line]
            paths = []
            for line in quoted:
                match = re.fullmatch(r'\s*umbrella( header)? "([^"]+)"\s*', line)
                assert match, "Unqualified module-map path directive"
                header = Path(match[2])
                assert header.is_absolute() and header.is_relative_to(checkout), "Foreign module-map umbrella"
                resolved = header.resolve(strict=True)
                assert resolved.is_relative_to(checkout), "Module-map umbrella escapes the selected checkout"
                assert resolved.is_file() if match[1] else resolved.is_dir(), "Module-map umbrella kind differs"
                paths.append(str(header.relative_to(app)))
            assert len(paths) == count, "Module-map root replacement is not confined to umbrellas"
            maps[name] = dict(before_sha256=before[name], after_sha256=hashlib.sha256(corrected).hexdigest(),
                              prefix_replacements=count, umbrellas=paths)
            changes[name] = corrected
        assert str(original_app.parent.parent).encode() not in corrected, "Stale generated compiler root"
        expected[name] = hashlib.sha256(corrected).hexdigest()
        assert actual[name] == (before[name] if apply else expected[name]), (name, "Unexpected generated input change")
    assert maps, "No generated module maps"
    # Validate every input before modifying any copy. The accepted root is read-only.
    if apply:
        for name, data in changes.items():
            (copied / name).write_bytes(data)
    assert generated_files(copied) == expected, "Generated relocation publication differs"
    return dict(status="QUALIFIED_GENERATED_RELOCATION", original_root=str(original), root=str(copied),
                files=expected, modulemaps=maps, generated_files=len(expected), relocated_modulemaps=len(maps),
                semantic_change="Exact arm-local umbrella prefix only; all other bytes equal accepted inputs")


def bind(root, arm=None):
    definition = json.loads((root / "definition.json").read_text())
    preparation = json.loads((root / "preparation.json").read_text())
    for path, fingerprint in definition["qualified_helper_sha256"].items():
        assert sha(path) == fingerprint, "Qualified helper changed"
    assert sha(__file__) == definition["adapter_sha256"], "Build adapter changed"
    return bind_sources(root, definition, preparation, arm)


def bind_sources(root, definition, preparation, arm=None):
    reference = Path(preparation["accepted_build_root"])
    spec = importlib.util.spec_from_file_location("accepted_app_build", reference / "build.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    original_inventory = module.generated_inventory

    def generated_inventory(app, sdk):
        result = original_inventory(app, sdk)
        directory = app / "Tuist/.build/tuist-derived"
        result["tuist-generated-compiler-inputs"] = {"root": str(directory), "files": generated_files(directory)}
        return result

    module.generated_inventory = generated_inventory
    assert sha(root / "relocation.json") == definition["relocation_sha256"], "Relocation receipt changed"
    module.ROOT = root
    module.ADMISSION = definition
    module.P.OLD = root
    admission = json.loads((root / arm / "build-admission.json").read_text()) if arm else None
    module.P.D["deadline"] = admission["deadline"] if admission else None
    module.P.DEADLINE = datetime.datetime.fromisoformat(admission["deadline"]).timestamp() if admission else 0
    for arm, paths in preparation["arms"].items():
        module.P.D["prepared_sources"][arm].update(app=paths["app"], sdk=paths["sdk"])

    def source_guard(arm, workspace_hash):
        from journey_builds import documentation_transition
        protected_paths, transition = documentation_transition(module.P.REPO, preparation)
        for relative, protected in protected_paths.items():
            path = module.P.REPO / relative
            if "sha256" in protected:
                assert sha(path) == protected["sha256"], "Protected document changed: " + relative
            else:
                assert subprocess.check_output(["git", "ls-files", "--stage", "--", relative], cwd=module.P.REPO, text=True) == protected["index"]
                actual = list(path.stat())[6:10]
                assert actual[0] == protected["stat"][0] and actual[2:] == protected["stat"][2:], "Protected configuration modification metadata changed"
        assert module.P.protected_state(module.P.REPO) == module.P.D["main_protected_state"]
        assert git(module.P.D["original_app_repo"], "status", "--porcelain") == ""
        for name, fingerprint in module.P.D["preserve_existing_preparation"].items():
            assert sha(Path(module.P.D["existing_preparation_checkout"]) / name) == fingerprint
        manifest = json.loads((root / (arm + "-source-manifest.json")).read_text())
        for kind in ("app", "sdk"):
            directory = Path(preparation["arms"][arm][kind])
            expected = manifest[kind + "_tracked_files"]
            tracked = set(git(directory, "ls-files", "-z").split("\0")) - {""}
            links = {name for name in tracked if (directory / name).is_symlink()}
            assert links == ({".agents/skills"} if kind == "sdk" else set())
            assert tracked - links == set(expected)
            if links:
                link = directory / ".agents/skills"
                assert os.readlink(link) == "../.claude/skills" and link.resolve().is_relative_to(directory)
                assert git(directory, "rev-parse", "HEAD:.agents/skills") == "454b8427cd757f30dc7fdb9a325d19c399770417"
            assert git(directory, "rev-parse", "HEAD") == manifest["app_revision" if kind == "app" else "sdk_revision"]
            for name, fingerprint in expected.items():
                assert sha(directory / name) == fingerprint, (kind, name, "source changed")
            unknown = git(directory, "ls-files", "--others", "--exclude-standard").splitlines()
            allowed = manifest[kind + "_untracked_files"]
            assert set(unknown) == set(allowed), (kind, "untracked input changed")
            for name, fingerprint in allowed.items():
                assert sha(directory / name) == fingerprint
        app = Path(preparation["arms"][arm]["app"])
        assert sha(app / "DatadogApp.xcworkspace/contents.xcworkspacedata") == workspace_hash
        pins = json.loads((app / "Tuist/Package.resolved").read_text())["pins"]
        assert len(pins) == 64 and {item["identity"]: item for item in pins} == manifest["non_sdk_package_pins"]
        checkouts = list((app / "Tuist/.build/checkouts").iterdir())
        assert len(checkouts) == 64
        revisions = {item["state"]["revision"]: item["identity"] for item in pins}
        found = set()
        for checkout in checkouts:
            head = git(checkout, "rev-parse", "HEAD")
            assert head in revisions and revisions[head] not in found, "Foreign dependency revision"
            found.add(revisions[head])
            assert not git(checkout, "diff", "HEAD", "--"), "Modified dependency source"
            unknown = git(checkout, "ls-files", "--others", "--exclude-standard").splitlines()
            assert all(name.startswith(".build/") for name in unknown), "Foreign dependency source"
        assert found == {item["identity"] for item in pins}
        assert sha(module.P.D["swiftgen_binary"]) == module.P.D["swiftgen_sha256"]
        return {"tracked_app_sources": len(manifest["app_tracked_files"]), "tracked_sdk_files": len(manifest["sdk_tracked_files"]), "pins": 64, "protected_unchanged": True, "workspace_transition": transition}

    module.source_guard = source_guard
    module.has_documentation_transition = True
    return module, preparation


def freeze(root, arm):
    module, preparation = bind(root)
    paths = preparation["arms"][arm]
    app, sdk = Path(paths["app"]), Path(paths["sdk"])
    accepted = Path(preparation["accepted_build_root"])
    original = json.loads((accepted / (arm + "-source-manifest.json")).read_text())
    original_app = Path(preparation["accepted_source_root"]) / arm / "datadog-ios"
    overlay = preparation["overlay_sha256"]
    manifest = dict(original)
    for kind, directory in (("app", app), ("sdk", sdk)):
        expected = dict(original[kind + "_tracked_files"])
        if kind == "app":
            for name, fingerprint in overlay.items():
                if name in expected:
                    expected[name] = fingerprint
            expected["DatadogApp.xcworkspace/contents.xcworkspacedata"] = sha(original_app / "DatadogApp.xcworkspace/contents.xcworkspacedata")
        for name, fingerprint in expected.items():
            assert sha(directory / name) == fingerprint, (kind, name, "copy differs")
        manifest[kind + "_tracked_files"] = expected
        unknown = git(directory, "ls-files", "--others", "--exclude-standard").splitlines()
        if kind == "app":
            assert unknown == ["Targets/Platform/DatadogObservability/ReleaseValidationCapture.swift"], unknown
        else:
            assert all(name.startswith(("Datadog.xcodeproj/", "Derived/")) for name in unknown), unknown
        manifest[kind + "_untracked_files"] = {name: sha(directory / name) for name in unknown}
    for name, fingerprint in overlay.items():
        assert sha(app / name) == fingerprint, "Overlay differs"
    graph_receipt = project_graph(read_project(original_app), read_project(app))
    old_membership = project_membership(original_app)
    membership = project_membership(app)
    expected = dict(old_membership)
    expected["DatadogObservability"] = sorted(expected["DatadogObservability"] + ["Targets/Platform/DatadogObservability/ReleaseValidationCapture.swift"])
    assert membership == expected, "App compiler membership is not the single reviewed addition"
    save(root / (arm + "-source-manifest.json"), manifest)
    original_freeze = json.loads((accepted / arm / "build-input-freeze.json").read_text())
    relocation = relocated_inputs(original_app, app)
    assert relocation == json.loads((root / "relocation.json").read_text())[arm], "Generated relocation differs"
    generated = module.generated_inventory(app, sdk)
    original_generated = {name: value for name, value in generated.items() if name != "tuist-generated-compiler-inputs"}
    assert set(original_generated) == set(original_freeze["generated"]), "Generated root inventory changed"
    for name, inventory in original_generated.items():
        expected = dict(original_freeze["generated"][name]["files"])
        if name == "app-project":
            expected["project.pbxproj"] = sha(app / "DatadogApp.xcodeproj/project.pbxproj")
        assert inventory["files"] == expected, (name, "Generated input changed outside the reviewed project addition")
    value = dict(original_freeze)
    value.update(status="FROZEN_BEFORE_CAPTURE_BUILD", arm=arm, defined_at=module.P.now(), deadline=module.P.D["deadline"],
                 source_guard=module.source_guard(arm, original_freeze["workspace_sha256"]),
                 generated=generated, generated_relocation=relocation, sdk_membership=module.sdk_membership(sdk),
                 app_membership=membership, project_graph_guard=graph_receipt, adapter_sha256=sha(__file__), admission_sha256=sha(root / "definition.json"),
                 capture_overlay_sha256=overlay, generation_disposition="APFS clone with one validation source and exact generated umbrella relocation; no regeneration")
    save(root / arm / "build-input-freeze.json", value)
    print(json.dumps({"arm": arm, "status": value["status"], "app_targets": len(membership), "sdk_frameworks": len(value["sdk_membership"])}), flush=True)


def build(root, arm):
    started = datetime.datetime.now(datetime.timezone.utc)
    definition = json.loads((root / "definition.json").read_text())
    assert definition["limits"]["arm_total_seconds"] == 2100
    save(root / arm / "build-admission.json", {"state": "ADMITTED_BUILD_ONLY", "started_at": started.isoformat(), "deadline": (started + datetime.timedelta(seconds=2100)).isoformat(), "definition_sha256": sha(root / "definition.json"), "retries": 0})
    module, preparation = bind(root, arm)
    module.main(arm)
    compiler_membership(root, arm)


def compiler_membership(root, arm):
    preparation = json.loads((root / "preparation.json").read_text())
    app = Path(preparation["arms"][arm]["app"])
    freeze_record = json.loads((root / arm / "build-input-freeze.json").read_text())
    assert json.loads((root / arm / "build-receipt.json").read_text())["status"] == "PASS"
    result = {}
    for target, platforms in {"DatadogApp": {"Debug-iphonesimulator"},
                              "DatadogObservability": {"Debug-iphonesimulator", "Debug-watchsimulator"}}.items():
        expected = sorted(name for name in freeze_record["app_membership"][target] if name.endswith(".swift"))
        matches, actual_platforms = {}, set()
        for path in (root / arm / "DerivedData").rglob(target + ".SwiftFileList"):
            if not target_source_list(path, target):
                continue
            names = [str(Path(name).relative_to(app)) for name in shlex.split(path.read_text())]
            assert sorted(names) == expected, (target, "actual compiled source differs")
            platform = path.parents[3].name
            assert platform not in actual_platforms, "Duplicate target/platform source list"
            actual_platforms.add(platform)
            matches[str(path)] = {"sources": sorted(names), "sha256": sha(path)}
        assert actual_platforms == platforms, (target, "missing or foreign compiler platform")
        result[target] = matches
    save(root / arm / "capture-compiler-receipt.json", {"status": "PASS", "compiled_membership": result,
         "source_freeze_sha256": sha(root / arm / "build-input-freeze.json"), "classifier_sha256": sha(__file__), "native_launches": 0})


def target_source_list(path, target):
    # Project and target directories can share a name; bind the immediate target.
    return (path.name == target + ".SwiftFileList" and path.parent.name == "arm64"
            and path.parents[1].name == "Objects-normal" and path.parents[2].name == target + ".build")



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["freeze", "build", "qualify-compiler"])
    parser.add_argument("root", type=Path)
    parser.add_argument("arm", choices=["baseline", "candidate"])
    args = parser.parse_args()
    {"freeze": freeze, "build": build, "qualify-compiler": compiler_membership}[args.operation](args.root.resolve(strict=True), args.arm)
