#!/usr/bin/env python3
"""Compile the platform-neutral handoff in full watchOS/macOS products."""
import json
from pathlib import Path
import shutil
import tempfile
import time
import run

base = run.base
attempt = Path(tempfile.mkdtemp(prefix="exp166-platforms-"))
print(attempt, flush=True)
sdk = attempt / "sdk"
sdk.mkdir()
for relative in base.PATHS:
    shutil.copytree(base.REPO / relative, sdk / relative)
sources = base.fingerprint(sdk)
package = base.package().replace("platforms: [.iOS(.v15)]", 'platforms: [.iOS(.v15), .watchOS(.v9), .macOS("12.6")]')
(sdk / "Package.swift").write_text(package)
result = {"experiment": "EXP-166", "source_identity": {k: v for k, v in sources.items() if k != "files"},
          "source_paths": base.PATHS, "package_manifest": package, "attempts": [], "xcode": base.call(["xcodebuild", "-version"]).strip()}
for product, platform in [("DatadogRUM", "watchOS"), ("DatadogCore", "macOS")]:
    for configuration in ["Debug", "Release"]:
        label = platform + "-" + configuration
        log = attempt / (label + ".log")
        command = ["xcodebuild", "build", "-quiet", "-scheme", product, "-configuration", configuration,
                   "-destination", "generic/platform=" + platform, "-derivedDataPath", str(attempt / "derived"),
                   "-resultBundlePath", str(attempt / (label + ".xcresult")), "CODE_SIGNING_ALLOWED=NO"]
        start = time.monotonic()
        status = "PASS"
        try:
            base.call(command, cwd=sdk, log=log)
        except RuntimeError:
            status = "FAIL"
        modules = sorted((attempt / "derived/Build/Intermediates.noindex").glob("**/" + product + ".swiftmodule"))
        modules = [m for m in modules if configuration in str(m.relative_to(attempt))]
        entry = {"product": product, "platform": platform, "configuration": configuration,
                 "status": status, "command": command, "seconds": round(time.monotonic() - start, 2),
                 "log": str(log), "log_sha256": base.digest(log),
                 "swiftmodules": {str(m.relative_to(attempt)): base.digest(m) for m in modules if m.is_file()}}
        result["attempts"].append(entry)
        (attempt / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({k: entry[k] for k in ["product", "platform", "configuration", "status", "seconds"]}), flush=True)
        if status != "PASS":
            raise SystemExit(1)
result["source_unchanged"] = all(base.digest(sdk / path) == digest for path, digest in sources["files"].items())
result["package_unchanged"] = (sdk / "Package.swift").read_text() == package
(attempt / "result.json").write_text(json.dumps(result, indent=2) + "\n")
