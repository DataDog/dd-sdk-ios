"""Validate a pre-SDK physical fixture receipt against every signed Mach-O file."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re

MAGIC = {bytes.fromhex(value) for value in
         ("cffaedfe", "feedfacf", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
FIELDS = {"schemaVersion", "runID", "sourceRevision", "processID", "bundleIdentifier",
          "boundary", "executable", "binaries"}


def require(value, label):
    if not value:
        raise ValueError(label)


def inventory(app):
    app = Path(app)
    with (app / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    binaries = {}
    for path in sorted(app.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as source:
            header = source.read(4)
            if header not in MAGIC:
                continue
            digest = hashlib.sha256(header)
            for chunk in iter(lambda: source.read(65536), b""):
                digest.update(chunk)
        binaries[str(path.relative_to(app))] = digest.hexdigest()
    executable = info["CFBundleExecutable"]
    require(executable in binaries, "signed main executable missing from Mach-O inventory")
    return {"bundleIdentifier": info["CFBundleIdentifier"], "executable": executable,
            "binaries": binaries}


def read_receipt(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate receipt key")
            result[key] = value
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=unique)


def validate(receipt, app, run_id, revision, process_id):
    require(re.fullmatch("[a-z0-9-]+", run_id), "invalid expected run ID")
    require(re.fullmatch("[a-f0-9]{40}", revision), "invalid expected source revision")
    require(type(process_id) is int and process_id > 0, "invalid expected process ID")
    require(isinstance(receipt, dict) and set(receipt) == FIELDS, "receipt shape changed")
    require(type(receipt["schemaVersion"]) is int and receipt["schemaVersion"] == 1, "receipt schema changed")
    require(receipt["runID"] == run_id and receipt["sourceRevision"] == revision, "stale run/source identity")
    require(type(receipt["processID"]) is int and receipt["processID"] == process_id, "wrong native process")
    require(receipt["boundary"] == "before-sdk-initialization", "late installed identity boundary")
    expected = inventory(app)
    for key in ("bundleIdentifier", "executable", "binaries"):
        require(receipt[key] == expected[key], "installed " + key + " differs from signed build")
    return {"state": "PASS", "run_id": run_id, "source_revision": revision,
            "process_id": process_id, "boundary": receipt["boundary"], **expected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--signed-app", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--process-id", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = validate(read_receipt(args.receipt), args.signed_app,
                      args.run_id, args.source_revision, args.process_id)
    with args.output.open("x") as output:
        json.dump(result, output, indent=2, sort_keys=True)
        output.write("\n")
    print(json.dumps({"installed_identity": result["state"], "binaries": len(result["binaries"])}))


if __name__ == "__main__":
    main()
