#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Performance Timeseries — Plan 1 + Sampling Demo
# AI-first POD | Week 1 | April 18, 2026
# ============================================================================
#
# Configure these paths for your machine:
#
IOS_SDK_PATH="$HOME/go/src/github.com/DataDog/dd-sdk-ios"
ANDROID_SDK_PATH="$HOME/dd/sdks/dd-sdk-android"
JAVA_HOME_PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
#
# ============================================================================

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

separator() {
    echo ""
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
    echo ""
}

heading() {
    echo -e "${BOLD}${CYAN}$1${RESET}"
}

subheading() {
    echo -e "${BOLD}$1${RESET}"
}

narrate() {
    echo -e "${DIM}$1${RESET}"
}

pause() {
    echo ""
    read -r -p "  [press enter to continue]"
    echo ""
}

IOS_PACKAGE="$IOS_SDK_PATH/DatadogTimeseries"

# ============================================================================
clear
echo ""
heading "  PERFORMANCE TIMESERIES — Week 1"
echo ""
narrate "  AI-first POD | Sprint 1 | RUM-13949"
narrate "  Barbora Plasovska | April 18, 2026"
separator

heading "This Week"
echo ""
echo "  1. Built and verified the business logic pipeline — a standalone,"
echo "     platform-agnostic package that takes timestamped performance samples"
echo "     and produces complete RUM timeseries JSON events."
echo "     Tested on both iOS (Swift) and Android (Kotlin)."
echo ""
echo "  2. Researched sampling strategies and algorithms — how much data can"
echo "     we cut without losing meaningful signal."
pause

# ============================================================================
separator
heading "1/2  Business Logic Pipeline"
echo ""
echo "  Built a standalone, platform-agnostic pipeline that implements"
echo "  the core business logic of the timeseries feature."
echo ""
echo "  What the pipeline does:"
echo "    Takes timestamped performance samples (memory, CPU — sampled every 1s)"
echo "    and transforms them into complete RUM timeseries JSON events."
echo ""
echo "    Samples  -->  Batcher  -->  Event Builder  -->  JSON Encoder  -->  RUM JSON"
echo ""
echo "  Zero SDK dependencies — pure logic, tested on both iOS (Swift)"
echo "  and Android (Kotlin) against the same expected fixtures."
echo "  This is the foundation everything else builds on."
pause

separator
narrate "  iOS — dd-sdk-ios/DatadogTimeseries/"
echo ""

if [ ! -d "$IOS_PACKAGE" ]; then
    echo -e "  ${YELLOW}Skipped — $IOS_PACKAGE not found${RESET}"
else
    cd "$IOS_PACKAGE"
    TEST_OUTPUT=$(swift test 2>&1)
    PASSED=$(echo "$TEST_OUTPUT" | grep -E "Executed [0-9]+ tests" | tail -1 || true)
    if [ -n "$PASSED" ]; then
        echo -e "  ${GREEN}✓  $PASSED${RESET}"
    else
        echo -e "  ${GREEN}✓  Tests passed${RESET}"
    fi
fi

echo ""
narrate "  Android — dd-sdk-android/DatadogTimeseries/"
echo ""

ANDROID_PACKAGE="$ANDROID_SDK_PATH/DatadogTimeseries"
if [ ! -d "$ANDROID_PACKAGE" ]; then
    echo -e "  ${YELLOW}Skipped — $ANDROID_PACKAGE not found${RESET}"
else
    cd "$ANDROID_PACKAGE"
    GRADLE_OUTPUT=$(JAVA_HOME="$JAVA_HOME_PATH" ./gradlew cleanTest test 2>&1)
    PASSED_COUNT=$(echo "$GRADLE_OUTPUT" | grep -c " PASSED" || true)
    FAILED_COUNT=$(echo "$GRADLE_OUTPUT" | grep -c " FAILED" || true)
    if [ "$PASSED_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}✓  Executed $PASSED_COUNT tests, with $FAILED_COUNT failures${RESET}"
    else
        SUMMARY=$(echo "$GRADLE_OUTPUT" | grep -E "[0-9]+ tests completed" | tail -1 || true)
        if [ -n "$SUMMARY" ]; then
            echo -e "  ${GREEN}✓  $SUMMARY${RESET}"
        else
            echo -e "  ${GREEN}✓  Tests passed${RESET}"
        fi
    fi
fi
pause

separator
echo "  Both platforms verify against the SAME expected JSON fixtures."
echo "  Same business logic → identical RUM events regardless of platform."
echo ""

FIXTURE_IOS="$IOS_SDK_PATH/DatadogTimeseries/Tests/DatadogTimeseriesTests/Fixtures/expected_memory_batch1.json"
FIXTURE_ANDROID="$ANDROID_SDK_PATH/DatadogTimeseries/src/test/resources/fixtures/expected_memory_batch1.json"

if [ -f "$FIXTURE_IOS" ] && [ -f "$FIXTURE_ANDROID" ]; then
    if diff -q "$FIXTURE_IOS" "$FIXTURE_ANDROID" > /dev/null 2>&1; then
        echo -e "  ${GREEN}iOS and Android fixtures are identical${RESET}"
    else
        echo -e "  ${YELLOW}Fixtures differ (check manually)${RESET}"
    fi

    echo ""
    subheading "  Sample event (memory_usage, batch 1):"
    echo ""
    if command -v python3 > /dev/null 2>&1; then
        python3 -m json.tool "$FIXTURE_IOS" 2>/dev/null | head -30 | sed 's/^/  /'
        LINES=$(python3 -m json.tool "$FIXTURE_IOS" 2>/dev/null | wc -l)
        if [ "$LINES" -gt 30 ]; then
            narrate "  ... ($(( LINES - 30 )) more lines)"
        fi
    else
        cat "$FIXTURE_IOS" | sed 's/^/  /'
    fi
else
    narrate "  (fixture files not found — skipping comparison)"
fi
pause

# ============================================================================
separator
heading "2/2  Sampling Strategies"
echo ""
echo "  As of right now, we collect one sample per second."
echo ""
echo "  For a 30-minute session:"
echo "    memory_usage  →  1,800 data points"
echo "    cpu_usage     →  1,800 data points"
echo "    total         →  3,600 data points per session"
echo ""
echo "  Most of that data is redundant."
echo "  Memory barely moves when the app is idle."
echo "  CPU is noisy — individual spikes matter, not every tick."
echo ""
echo "  Can we send less data without losing meaningful signal?"
pause

separator
subheading "  Three Strategies"
echo ""
echo "  1. PassThrough (current baseline)"
echo "     Every sample is forwarded. 60 samples in → 60 data points out."
echo "     No intelligence — maximum data, maximum cost."
echo ""
echo "  2. Deadband"
echo "     Only emit a sample when the value has changed by more than a threshold."
echo "     Memory sits at 31MB for 10 seconds → send nothing."
echo "     Memory jumps to 33MB → emit."
echo "     Good for: memory (slow-changing, allocation-driven)"
echo ""
echo "  3. Window Aggregate"
echo "     Collapse a time window into one representative value (max, avg, min)."
echo "     10 CPU samples over 5 seconds → emit the peak."
echo "     Good for: CPU (noisy, burst-driven)"
pause

separator
narrate "  Running all 3 against a 60-second fixture (60 samples per metric)..."
echo ""

if [ ! -d "$IOS_PACKAGE" ]; then
    echo -e "  ${YELLOW}Skipped — $IOS_PACKAGE not found${RESET}"
    pause
else
    cd "$IOS_PACKAGE"

    FIXTURE="$IOS_PACKAGE/Tests/DatadogTimeseriesTests/Fixtures/input_realistic_60s.csv"
    OUTPUT_DIR="$IOS_PACKAGE/output"
    rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"

    RUNNER_TMP="$(mktemp /tmp/ts-runner-output.XXXXXX.json)"
    trap 'rm -f "$RUNNER_TMP"' EXIT

    swift run DatadogTimeseriesRunner -- \
        --fixture-path "$FIXTURE" \
        --output-dir "$OUTPUT_DIR" \
        --threshold 1000000 \
        --heartbeat 30 \
        --window 5 \
        --aggregate max > "$RUNNER_TMP" 2>/dev/null

    echo -e "  ${GREEN}✓ Pipeline complete${RESET}"
    echo ""

    python3 - "$RUNNER_TMP" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

stats = data["stats"]
filters = ["passthrough", "deadband", "window"]
labels  = {"passthrough": "PassThrough", "deadband": "Deadband (1MB)", "window": "Window (max, 5s)"}

pt_mem = stats["passthrough"]["memory"]["dataPointCount"]
pt_cpu = stats["passthrough"]["cpu"]["dataPointCount"]
pt_total = pt_mem + pt_cpu

col_w = [20, 13, 13, 13, 13, 13]
header = (
    f"  {'Filter':<{col_w[0]}}"
    f"{'Events(mem)':>{col_w[1]}}"
    f"{'Points(mem)':>{col_w[2]}}"
    f"{'Events(cpu)':>{col_w[3]}}"
    f"{'Points(cpu)':>{col_w[4]}}"
    f"{'Reduction':>{col_w[5]}}"
)
sep = "  " + "-" * sum(col_w)

print(header)
print(sep)
for f in filters:
    em = stats[f]["memory"]["eventCount"]
    dm = stats[f]["memory"]["dataPointCount"]
    ec = stats[f]["cpu"]["eventCount"]
    dc = stats[f]["cpu"]["dataPointCount"]
    total = dm + dc
    pct = round((1.0 - total / pt_total) * 100, 1) if pt_total > 0 else 0.0
    reduction = "--" if f == "passthrough" else f"{pct}%"
    print(
        f"  {labels[f]:<{col_w[0]}}"
        f"{em:>{col_w[1]}}"
        f"{dm:>{col_w[2]}}"
        f"{ec:>{col_w[3]}}"
        f"{dc:>{col_w[4]}}"
        f"{reduction:>{col_w[5]}}"
    )
PYEOF

    echo ""
    narrate "  Filtered output is backend-ready — same schema, fewer data points."
    echo ""

    python3 - "$RUNNER_TMP" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

raw = data.get("firstEvents", {}).get("deadband_memory", "")
if raw:
    parsed = json.loads(raw)
    ts_data = parsed.get("timeseries", {}).get("data", [])
    values_mb = [f"{round(p['data_point_value'] / 1e6, 1)}MB" for p in ts_data]
    print(f"  Deadband memory → {values_mb}")
    print(f"  Only the allocation jumps. Flat stretches between them: dropped.")
PYEOF

fi
pause

# ============================================================================
separator
heading "Next Steps"
echo ""
echo "  Integrate the pipeline into the SDK:"
echo "    - Replace CSVDataProvider with real VitalMemoryReader / VitalCPUReader"
echo "    - Wire into RUM session lifecycle and the upload pipeline"
echo "    - Test end-to-end: SDK → backend → query"
echo ""
echo "  Two open decisions to resolve along the way:"
echo "    Schema    — which data_point format does the backend adopt?"
echo "                (A: typed fields / B: single scalar / C: compound)"
echo "    Sampling  — per-metric strategy or one for all?"
echo "                e.g. Deadband for memory, Window for CPU"
separator
echo ""
narrate "  End of demo."
echo ""
