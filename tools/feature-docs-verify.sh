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

def print_fix_instructions(full_clone=False):
    """Print the standard recipe for fixing a feature-doc verification failure."""
    on_full_clone = " on a full clone" if full_clone else ""
    print(f"   Run the '/dd-sdk-ios:update-feature-docs' skill in Claude Code{on_full_clone} to refresh the doc,")
    print(f"   then `make feature-docs-verify` to confirm, and push the update.")

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
        print_fix_instructions()
        failed = True
        continue

    if not files:
        print(f"❌ {doc_name}: missing tracked_files in frontmatter.")
        print_fix_instructions()
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

    # `git diff` exits non-zero when the baseline commit isn't reachable
    # (e.g. shallow clone on a release/hotfix branch, or a typo in the
    # frontmatter). In that case stdout is empty, so we'd otherwise silently
    # report the doc as up to date. Treat any non-zero exit as a failure and
    # surface stderr so the engineer knows what to do.
    if result.returncode != 0:
        print(f"❌ {doc_name}: failed to diff against {commit}.")
        stderr = result.stderr.strip()
        if stderr:
            for stderr_line in stderr.splitlines():
                print(f"   {stderr_line}")
        print(f"   The baseline commit is not reachable in this checkout (often a shallow clone on a")
        print(f"   release/hotfix branch, or a typo in the frontmatter).")
        print_fix_instructions(full_clone=True)
        failed = True
    elif result.stdout.strip():
        print(f"❌ {doc_name} may be out of date.")
        print(f"   Public API changed since commit {commit}.")
        print_fix_instructions()
        failed = True
    else:
        print(f"✅ {doc_name} is up to date (verified at {commit}).")

# Each *_FEATURE.md must be wired into a few hand-maintained registries:
# - the Confluence publish workflow
# - AGENTS.md
# - docs/LLM_FEATURE_DOCS_GUIDELINES.md
# The Confluence workflow needs the path in TWO distinct places (the trigger
# `paths:` filter AND the `cp` block), so it gets a dedicated check that
# verifies both contexts separately. Other registries just need any mention.

WORKFLOW_PATH = ".github/workflows/changelog-to-confluence.yaml"
WORKFLOW_LABEL = "Confluence publish workflow"
SUBSTRING_REGISTRIES = [
    ("AGENTS.md", "AGENTS.md"),
    ("docs/LLM_FEATURE_DOCS_GUIDELINES.md", "LLM feature-docs guidelines"),
]

doc_rel_paths = sorted(os.path.relpath(d, repo_root) for d in docs)
registry_failed = False

print()
print("Checking that each feature doc is registered in:")
print(f"  - {WORKFLOW_PATH} (paths: filter AND cp block)")
for path, _ in SUBSTRING_REGISTRIES:
    print(f"  - {path}")

# --- Workflow check: two contexts must each contain the path ---
abs_workflow = os.path.join(repo_root, WORKFLOW_PATH)
if not os.path.exists(abs_workflow):
    print(f"⚠️  {WORKFLOW_LABEL}: file not found at {WORKFLOW_PATH} — skipping.")
else:
    with open(abs_workflow) as f:
        workflow_content = f.read()
    for rel in doc_rel_paths:
        # `paths:` filter entries appear as quoted YAML list items.
        in_paths_filter = (f"'{rel}'" in workflow_content) or (f'"{rel}"' in workflow_content)
        # `cp` lines start with `cp <relative_path> ...`.
        in_cp_block = f"cp {rel} " in workflow_content

        if not in_paths_filter and not in_cp_block:
            print(f"❌ {WORKFLOW_LABEL}: '{rel}' is missing from BOTH the `paths:` filter and the `cp` block.")
            registry_failed = True
        elif not in_paths_filter:
            print(f"❌ {WORKFLOW_LABEL}: '{rel}' is missing from the `paths:` filter")
            print(f"   (expected as `'{rel}'` under `on.push.paths`). Without it, doc-only updates won't trigger publishing.")
            registry_failed = True
        elif not in_cp_block:
            print(f"❌ {WORKFLOW_LABEL}: '{rel}' is missing from the `cp` block")
            print(f"   (expected as `cp {rel} publish_folder/...`). Without it, the page is never copied for publishing.")
            registry_failed = True

# --- Substring registries (AGENTS.md, LLM guidelines): any mention is enough ---
for registry_path, label in SUBSTRING_REGISTRIES:
    abs_path = os.path.join(repo_root, registry_path)
    if not os.path.exists(abs_path):
        print(f"⚠️  {label}: file not found at {registry_path} — skipping.")
        continue
    with open(abs_path) as f:
        content = f.read()
    for rel in doc_rel_paths:
        if rel not in content:
            print(f"❌ {label}: missing reference to '{rel}'.")
            registry_failed = True

if registry_failed:
    print_fix_instructions()
    failed = True
else:
    print(f"✅ All {len(doc_rel_paths)} feature doc(s) registered in every required location.")

sys.exit(1 if failed else 0)
EOF
