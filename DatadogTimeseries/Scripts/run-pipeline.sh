#!/usr/bin/env bash
# run-pipeline.sh — Run the DatadogTimeseries filter pipeline against the 60s fixture,
# print a comparison table, and write per-filter NDJSON output files.
#
# Usage:
#   ./scripts/run-pipeline.sh [options]
#
# Options:
#   --filter passthrough|deadband|window   Filter to pretty-print the first event from (default: passthrough)
#   --threshold <bytes>                    Deadband threshold in bytes (default: 1000000)
#   --heartbeat <seconds>                  Deadband heartbeat interval in seconds (default: 30)
#   --window <seconds>                     Window aggregate duration in seconds (default: 5)
#   --aggregate max|avg|min|last           Window aggregate function (default: max)

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
FILTER="passthrough"
THRESHOLD=1000000
HEARTBEAT=30
WINDOW=5
AGGREGATE="max"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)    FILTER="$2";    shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --heartbeat) HEARTBEAT="$2"; shift 2 ;;
        --window)    WINDOW="$2";    shift 2 ;;
        --aggregate) AGGREGATE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve package root (the directory containing Package.swift)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE_PATH="$PKG_ROOT/Tests/DatadogTimeseriesTests/Fixtures/input_realistic_60s.csv"
OUTPUT_DIR="$PKG_ROOT/output"

# ---------------------------------------------------------------------------
# Clear output directory
# ---------------------------------------------------------------------------
echo "Clearing output/ directory..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
echo ""
echo "Running swift test..."
cd "$PKG_ROOT"
if ! swift test 2>&1; then
    echo "" >&2
    echo "ERROR: swift test failed. Aborting." >&2
    exit 1
fi
echo "All tests passed."

# ---------------------------------------------------------------------------
# Run runner and capture JSON output to a temp file
# ---------------------------------------------------------------------------
echo ""
echo "Running pipeline across all filters..."
RUNNER_TMP="$(mktemp /tmp/ts-runner-output.XXXXXX.json)"
trap 'rm -f "$RUNNER_TMP"' EXIT

swift run DatadogTimeseriesRunner -- \
    --fixture-path "$FIXTURE_PATH" \
    --output-dir "$OUTPUT_DIR" \
    --threshold "$THRESHOLD" \
    --heartbeat "$HEARTBEAT" \
    --window "$WINDOW" \
    --aggregate "$AGGREGATE" > "$RUNNER_TMP"

# ---------------------------------------------------------------------------
# Parse stats and print comparison table
# ---------------------------------------------------------------------------
python3 - "$RUNNER_TMP" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

stats = data["stats"]
filters = ["passthrough", "deadband", "window"]
labels = {"passthrough": "PassThrough", "deadband": "Deadband", "window": "WindowAggregate"}

pt_dp_mem = stats["passthrough"]["memory"]["dataPointCount"]
pt_dp_cpu = stats["passthrough"]["cpu"]["dataPointCount"]
pt_total = pt_dp_mem + pt_dp_cpu

rows = []
for f in filters:
    ev_mem = stats[f]["memory"]["eventCount"]
    dp_mem = stats[f]["memory"]["dataPointCount"]
    ev_cpu = stats[f]["cpu"]["eventCount"]
    dp_cpu = stats[f]["cpu"]["dataPointCount"]
    total_dp = dp_mem + dp_cpu
    reduction = round((1.0 - total_dp / pt_total) * 100, 1) if pt_total > 0 else 0.0
    rows.append((labels[f], ev_mem, dp_mem, ev_cpu, dp_cpu, reduction))

col_w = [20, 13, 13, 13, 13, 13]
header = (
    f"{'Filter':<{col_w[0]}}"
    f"{'Events(mem)':>{col_w[1]}}"
    f"{'Points(mem)':>{col_w[2]}}"
    f"{'Events(cpu)':>{col_w[3]}}"
    f"{'Points(cpu)':>{col_w[4]}}"
    f"{'Reduction %':>{col_w[5]}}"
)
sep = "-" * sum(col_w)

print("")
print("Filter comparison (fixture: input_realistic_60s.csv)")
print(sep)
print(header)
print(sep)
for (label, em, dm, ec, dc, red) in rows:
    print(
        f"{label:<{col_w[0]}}"
        f"{em:>{col_w[1]}}"
        f"{dm:>{col_w[2]}}"
        f"{ec:>{col_w[3]}}"
        f"{dc:>{col_w[4]}}"
        f"{str(red) + '%':>{col_w[5]}}"
    )
print(sep)
PYEOF

# ---------------------------------------------------------------------------
# List written output files
# ---------------------------------------------------------------------------
echo ""
echo "Output files written to output/:"
ls -1 "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Pretty-print first event from selected filter (memory metric)
# ---------------------------------------------------------------------------
python3 - "$RUNNER_TMP" "$FILTER" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

selected_filter = sys.argv[2]
key = f"{selected_filter}_memory"
raw = data.get("firstEvents", {}).get(key, "")
print(f"\nFirst event from filter '{selected_filter}' (memory_usage):")
if raw:
    parsed = json.loads(raw)
    print(json.dumps(parsed, indent=2, sort_keys=True))
else:
    print("(no event)")
PYEOF
