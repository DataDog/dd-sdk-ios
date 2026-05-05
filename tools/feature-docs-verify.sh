#!/bin/bash
# Verifies that feature docs are up to date with the public API.
# Discovers all *_FEATURE.md files in the repo. Each doc's frontmatter is the
# source of truth: `verified_against_commit` and `tracked_files` drive the check.
# Run `make feature-docs-verify` to execute.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" <<'EOF'
import os
import subprocess
import sys

repo_root = sys.argv[1]
failed = False

def parse_frontmatter(path):
    """Return (verified_against_commit, tracked_files) from a doc's YAML frontmatter."""
    commit = None
    files = []
    in_front = False   # True once we've seen the opening ---
    in_files = False   # True while we're inside the tracked_files list

    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")

            # --- marks both the opening and closing of the frontmatter block
            if line == "---":
                if not in_front:
                    in_front = True
                    continue
                else:
                    break  # closing ---, stop parsing

            if not in_front:
                continue

            if line.startswith("verified_against_commit:"):
                commit = line.split(":", 1)[1].strip()
                in_files = False
            elif line.startswith("tracked_files:"):
                in_files = True
            elif in_files and line.startswith("  - "):
                # Each list entry is "  - path/to/file.swift"
                files.append(line[4:].strip())
            elif line and not line.startswith(" "):
                # Any non-indented key ends the tracked_files list
                in_files = False

    return commit, files

# Discover all *_FEATURE.md files, skipping generated output directories
docs = []
for dirpath, dirnames, filenames in os.walk(repo_root):
    dirnames[:] = [d for d in dirnames if d not in ("build", "artifacts")]
    for name in filenames:
        if name.endswith("_FEATURE.md"):
            docs.append(os.path.join(dirpath, name))

if not docs:
    print("No *_FEATURE.md files found.")
    sys.exit(0)

for doc in sorted(docs):
    doc_name = os.path.basename(doc)
    commit, files = parse_frontmatter(doc)

    if not commit:
        print(f"❌ {doc_name}: missing verified_against_commit in frontmatter.")
        failed = True
        continue

    if not files:
        print(f"❌ {doc_name}: missing tracked_files in frontmatter.")
        failed = True
        continue

    # Check whether any tracked file changed since the doc was last verified
    print(f"Checking {doc_name} against:")
    for f in files:
        print(f"  - {f}")
    abs_files = [os.path.join(repo_root, f) for f in files]
    result = subprocess.run(
        ["git", "-C", repo_root, "diff", f"{commit}..HEAD", "--", *abs_files],
        capture_output=True, text=True
    )

    if result.stdout.strip():
        print(f"❌ {doc_name} may be out of date.")
        print(f"   Public API changed since commit {commit}.")
        print(f"   Run the '/dd-sdk-ios:update-feature-docs' skill in Claude Code to update it.")
        failed = True
    else:
        print(f"✅ {doc_name} is up to date (verified at {commit}).")

sys.exit(1 if failed else 0)
EOF
