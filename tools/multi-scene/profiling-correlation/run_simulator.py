#!/usr/bin/env python3
"""Build and validate EXP-187 simulator mechanics; never certify T14 profiling."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "acceptance"))
from acceptance import file_hash, now, protected_state, save
from validate import validate_native, require

SOURCE_ROOTS = [
    "DatadogCore/Sources", "DatadogInternal/Sources", "DatadogRUM/Sources",
    "DatadogProfiling/Sources", "DatadogProfiling/Mach", "DatadogTrace/Sources", "DatadogLogs/Sources",
    "DatadogWebViewTracking/Sources", "DatadogSessionReplay/Sources",
    "DatadogCrashReporting/Sources", "BenchmarkTests/Runner",
    "BenchmarkTests/Benchmarks/Sources", "BenchmarkTests/Benchmarks/Package.swift",
    "BenchmarkTests/BenchmarkTests.xcodeproj/project.pbxproj",
    "BenchmarkTests/BenchmarkTests.xcodeproj/xcshareddata",
    "BenchmarkTests/BenchmarkTests.xcodeproj/project.xcworkspace/xcshareddata",
    "Package.swift", "Package.resolved", "BenchmarkTests/xcconfigs/Runner.xcconfig",
    "xcconfigs/Datadog.xcconfig", "xcconfigs/Base.xcconfig",
    "tools/multi-scene/profiling-correlation",
    "tools/multi-scene/acceptance",
]


def source_identity(repo):
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--", *SOURCE_ROOTS], cwd=repo).decode().split("\0")
    files = {p: file_hash(repo / p) for p in sorted(paths) if p}
    require(not any(p.endswith("Datadog.local.xcconfig") for p in files), "protected configuration in inventory")
    return {"sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
            "files": files, "file_count": len(files)}


def scene_manifest(info):
    result = dict(info)
    result["UIApplicationSceneManifest"] = {
        "UIApplicationSupportsMultipleScenes": False,
        "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
            "UISceneConfigurationName": "Profiling Acceptance",
            "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).ProfilingAcceptanceSceneDelegate",
        }]},
    }
    return result


def require_configuration(info):
    configuration = info.get("DatadogConfiguration", {})
    token = configuration.get("ClientToken", "")
    application_id = configuration.get("ApplicationID", "")
    require(isinstance(token, str) and bool(token.strip()) and "$(" not in token,
            "built acceptance app has no resolved client token")
    try:
        uuid.UUID(application_id)
    except (ValueError, AttributeError, TypeError):
        raise ValueError("built acceptance app has no valid RUM application ID") from None


class SimulatorRun:
    def __init__(self, args):
        self.args = args
        self.repo = args.repo.resolve()
        self.out = args.output.resolve()
        require(not self.out.exists(), "output already exists; use a fresh attempt")
        self.out.mkdir(parents=True)
        self.run_id = "exp187-" + str(uuid.uuid4())
        self.environment = dict(os.environ, DEVELOPER_DIR=args.developer_dir,
                                DD_BENCHMARK="1", OTEL_SWIFT="1", SKIP_LINT="1")
        self.summary = {
            "schema_version": 1, "experiment": "EXP-187", "gate": "T14",
            "gate_status": "INCONCLUSIVE", "native_validation": "NOT_RUN",
            "backend_validation": "NOT_RUN", "run_id": self.run_id,
            "scope": "ORDINARY_BUILD_ONLY" if args.ordinary_build_only else "SIMULATOR_MECHANICS_ONLY",
            "started_at": now(), "artifact_root": str(self.out), "stages": {},
            "remaining": ["supported physical native wall-time stack samples", "complete backend RUM/profile inventory",
                          "exact profile attachment and process labels"],
        }
        self.protected = protected_state(self.repo)
        self.bundle = None
        self.installed = False
        self.frozen = None

    def stage(self, name, details):
        self.summary["stages"][name] = details
        save(self.out / "summary.json", self.summary)
        print(json.dumps({"stage": name, "run_id": self.run_id, **details}), flush=True)

    def command(self, args, name, check=True, timeout=1200):
        with (self.out / (name + ".log")).open("x") as output:
            result = subprocess.run(args, cwd=self.repo, env=self.environment,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        require(not check or result.returncode == 0, name + " failed; inspect scoped artifact")
        return result.returncode

    def capture(self, args):
        return subprocess.check_output(args, cwd=self.repo, env=self.environment,
                                       text=True, stderr=subprocess.DEVNULL).strip()

    def execute(self):
        try:
            self.summary["revision"] = self.capture(["git", "rev-parse", "HEAD"])
            require(not self.capture(["git", "status", "--porcelain=v1", "--", *SOURCE_ROOTS]),
                    "SDK/fixture/runner source is uncommitted")
            headers = self.capture(["git", "cat-file", "commit", self.summary["revision"]]).split("\n\n", 1)[0]
            signed = any(line.startswith(("gpgsig ", "gpgsig-sha256 ")) for line in headers.splitlines())
            if signed:
                self.command(["git", "verify-commit", self.summary["revision"]], "signature")
            self.summary["signature"] = "VERIFIED" if signed else "UNSIGNED"
            self.summary["xcode"] = self.capture(["xcodebuild", "-version"])
            self.frozen = source_identity(self.repo)
            save(self.out / "source-identity.json", self.frozen)
            self.summary["source_fingerprint"] = self.frozen["sha256"]
            if not self.args.ordinary_build_only:
                require(self.args.device, "explicit freshly discovered simulator UUID required")
                devices = json.loads(self.capture(["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]
                matches = [(runtime, d) for runtime, values in devices.items()
                           for d in values if d["udid"] == self.args.device]
                require(len(matches) == 1 and "iOS-" in matches[0][0], "selected iOS simulator unavailable")
                runtime, device = matches[0]
                self.summary["device"] = dict(device, runtime=runtime)
                if device["state"] != "Booted":
                    self.command(["xcrun", "simctl", "boot", self.args.device], "boot")
                self.command(["xcrun", "simctl", "bootstatus", self.args.device, "-b"], "boot-ready")
            self.stage("preflight", {"state": "PASS"})

            command = ["xcodebuild", "build", "-quiet", "-project",
                       "BenchmarkTests/BenchmarkTests.xcodeproj", "-scheme", "Runner",
                       "-configuration", "Release", "-destination", "generic/platform=iOS Simulator",
                       "-derivedDataPath", str(self.out / "derived"),
                       "-resultBundlePath", str(self.out / "build.xcresult"), "CODE_SIGNING_ALLOWED=NO"]
            if not self.args.ordinary_build_only:
                # This tracked template contains build-variable placeholders, not resolved credentials.
                info = plistlib.loads((self.repo / "BenchmarkTests/Runner/Info.plist").read_bytes())
                info_path = self.out / "Acceptance-Info.plist"
                info_path.write_bytes(plistlib.dumps(scene_manifest(info)))
                config_path = self.out / "Acceptance.xcconfig"
                config_path.write_text(
                    '#include "' + str(self.repo / "BenchmarkTests/xcconfigs/Runner.xcconfig") + '"\n'
                    '#include? "' + str(self.repo / "xcconfigs/Datadog.local.xcconfig") + '"\n'
                    'CLIENT_TOKEN = $(DATADOG_CLIENT_TOKEN)\n')
                command += ["-xcconfig", str(config_path),
                            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MULTISCENE_PROFILING_ACCEPTANCE",
                            "INFOPLIST_FILE=" + str(info_path)]
            save(self.out / "build-command.json", command)
            self.command(command, "build")
            require(source_identity(self.repo) == self.frozen, "source changed during build")
            app = self.out / "derived/Build/Products/Release-iphonesimulator/Runner.app"
            # Only bundle identity is retained from the built property list.
            info = plistlib.loads((app / "Info.plist").read_bytes())
            if not self.args.ordinary_build_only:
                require_configuration(info)
                self.stage("configuration", {"state": "PASS", "client_token_resolved": True,
                                               "application_id_valid": True})
            self.bundle = info["CFBundleIdentifier"]
            executable = info["CFBundleExecutable"]
            require(self.bundle == "com.datadoghq.benchmarks.Runner", "unexpected benchmark bundle")
            binary_hash = file_hash(app / executable)
            self.summary["build"] = {
                "executable_sha256": binary_hash,
                "uuid": self.capture(["xcrun", "dwarfdump", "--uuid", str(app / executable)]),
                "bundle": self.bundle,
            }
            self.stage("build", {"state": "PASS"})
            if self.args.ordinary_build_only:
                require("UIApplicationSceneManifest" not in info, "ordinary lifecycle changed")
                symbols = self.capture(["xcrun", "nm", str(app / executable)])
                require("ProfilingAcceptance" not in symbols, "acceptance code leaked into ordinary build")
                self.stage("ordinary_compatibility", {"state": "PASS", "acceptance_symbols_absent": True,
                                                       "scene_manifest_absent": True})
                return

            self.command(["xcrun", "simctl", "terminate", self.args.device, self.bundle], "terminate-before", check=False)
            self.command(["xcrun", "simctl", "uninstall", self.args.device, self.bundle], "uninstall", check=False)
            absent = self.command(["xcrun", "simctl", "get_app_container", self.args.device, self.bundle, "data"],
                                  "container-absence", check=False)
            absence = (self.out / "container-absence.log").read_text()
            require(absent != 0 and ("No such file or directory" in absence or "not installed" in absence),
                    "clean installation absence not proven")
            self.command(["xcrun", "simctl", "install", self.args.device, str(app)], "install")
            self.installed = True
            installed = Path(self.capture(["xcrun", "simctl", "get_app_container", self.args.device, self.bundle, "app"]))
            require(file_hash(installed / executable) == binary_hash, "installed executable differs")
            data = Path(self.capture(["xcrun", "simctl", "get_app_container", self.args.device, self.bundle, "data"]))
            receipt_path = data / "Documents" / (self.run_id + ".json")
            require(not receipt_path.exists(), "restored receipt")
            self.stage("clean_install", {"state": "PASS", "absent_before_install": True,
                                        "installed_binary_sha256": binary_hash})
            self.environment.update(SIMCTL_CHILD_MULTISCENE_PROFILE_RUN_ID=self.run_id,
                                    SIMCTL_CHILD_MULTISCENE_PROFILE_SOURCE_REVISION=self.summary["revision"])
            launch = self.capture(["xcrun", "simctl", "launch",
                                   "--stdout=" + str(self.out / "app.stdout.log"),
                                   "--stderr=" + str(self.out / "app.stderr.log"),
                                   self.args.device, self.bundle])
            pid = int(launch.rsplit(":", 1)[1].strip())
            self.summary["pid"] = pid
            deadline = time.monotonic() + 180
            receipt = None
            while time.monotonic() < deadline:
                if receipt_path.exists():
                    receipt = json.loads(receipt_path.read_text())
                    if receipt.get("nativeStatus") != "RUNNING":
                        break
                time.sleep(0.25)
            require(receipt is not None, "native receipt missing")
            save(self.out / "native-receipt.json", receipt)
            expected = validate_native(receipt, self.run_id, self.summary["revision"], allow_simulator=True)
            require(receipt["processID"] == pid, "receipt came from another process")
            self.summary["native_validation"] = "PASS"
            self.summary["native_inventory"] = {"assertions": len(receipt["checkpoints"]),
                                                 "views": len(receipt["observations"]["views"]),
                                                 "operation_steps": len(receipt["observations"]["operations"]),
                                                 "profile_start_ids": [v["id"] for v in expected]}
            self.stage("native_validation", {"state": "PASS", **self.summary["native_inventory"]})
        except Exception as error:
            self.summary["gate_status"] = "INVALID"
            # Command output stays in scoped logs; exceptions never include local configuration.
            self.summary["failure"] = str(error)
            print(json.dumps({"run_id": self.run_id, "state": "INVALID", "reason": str(error)}), flush=True)
        finally:
            if self.installed:
                try:
                    self.command(["xcrun", "simctl", "terminate", self.args.device, self.bundle], "terminate-after", check=False)
                except Exception:
                    self.summary.update(gate_status="INVALID", failure="app cleanup failed")
            try:
                require(protected_state(self.repo) == self.protected, "protected workspace metadata changed")
                if self.frozen is not None:
                    require(source_identity(self.repo) == self.frozen, "frozen source changed")
                    require(self.capture(["git", "rev-parse", "HEAD"]) == self.summary["revision"], "HEAD changed")
                self.summary["workspace_preserved"] = True
            except Exception as error:
                self.summary.update(gate_status="INVALID", failure=str(error), workspace_preserved=False)
            self.summary["finished_at"] = now()
            save(self.out / "summary.json", self.summary)
            durable = self.repo / "DatadogRUM/MultiSceneSupport/Results/acceptance" / (self.run_id + ".json")
            with durable.open("x") as output:
                output.write(json.dumps(self.summary, indent=2, sort_keys=True) + "\n")
            print(json.dumps({"durable": str(durable), "gate_status": self.summary["gate_status"],
                              "native_validation": self.summary["native_validation"]}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="Fresh nonexistent artifact directory")
    parser.add_argument("--device", help="Freshly discovered simulator UUID")
    parser.add_argument("--developer-dir", required=True)
    parser.add_argument("--ordinary-build-only", action="store_true")
    runner = SimulatorRun(parser.parse_args())
    runner.execute()
    raise SystemExit(1 if runner.summary["gate_status"] == "INVALID" else 0)


if __name__ == "__main__":
    main()
