#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Performance Timeseries — Plan 1 Demo Script
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

# ============================================================================
clear
echo ""
heading "  PERFORMANCE TIMESERIES — Plan 1 Demo"
echo ""
narrate "  AI-first POD | Sprint 1 | RUM-13949"
narrate "  Barbora Plasovska | April 18, 2026"
separator

heading "This Week's Focus"
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

# ============================================================================
separator
heading "1/4  iOS Pipeline (Swift)"
echo ""
narrate "  Package: dd-sdk-ios/DatadogTimeseries/"
narrate "  Running: swift test"
echo ""

IOS_PACKAGE="$IOS_SDK_PATH/DatadogTimeseries"
if [ ! -d "$IOS_PACKAGE" ]; then
    echo -e "  ${YELLOW}Skipped — $IOS_PACKAGE not found${RESET}"
else
    cd "$IOS_PACKAGE"
    swift test 2>&1 | grep -E "Test Suite|test.*passed|test.*failed|All tests" | while IFS= read -r line; do
        if echo "$line" | grep -q "passed"; then
            echo -e "  ${GREEN}$line${RESET}"
        elif echo "$line" | grep -q "failed"; then
            echo -e "  ${YELLOW}$line${RESET}"
        else
            echo -e "  $line"
        fi
    done
fi
pause

# ============================================================================
separator
heading "2/4  Android Pipeline (Kotlin)"
echo ""
narrate "  Package: dd-sdk-android/DatadogTimeseries/"
narrate "  Running: ./gradlew cleanTest test"
echo ""

ANDROID_PACKAGE="$ANDROID_SDK_PATH/DatadogTimeseries"
if [ ! -d "$ANDROID_PACKAGE" ]; then
    echo -e "  ${YELLOW}Skipped — $ANDROID_PACKAGE not found${RESET}"
else
    cd "$ANDROID_PACKAGE"
    JAVA_HOME="$JAVA_HOME_PATH" ./gradlew cleanTest test 2>&1 | grep -E "PASSED|FAILED" | while IFS= read -r line; do
        if echo "$line" | grep -q "PASSED"; then
            echo -e "  ${GREEN}$line${RESET}"
        else
            echo -e "  ${YELLOW}$line${RESET}"
        fi
    done
fi
pause

# ============================================================================
separator
heading "3/4  Cross-Platform Fixture Match"
echo ""
echo "  Both platforms verify against the SAME expected JSON fixtures."
echo "  This proves the business logic produces identical RUM events"
echo "  regardless of platform."
echo ""

FIXTURE_IOS="$IOS_SDK_PATH/DatadogTimeseries/Tests/DatadogTimeseriesTests/Fixtures/expected_memory_batch1.json"
FIXTURE_ANDROID="$ANDROID_SDK_PATH/DatadogTimeseries/src/test/resources/fixtures/expected_memory_batch1.json"

if [ -f "$FIXTURE_IOS" ] && [ -f "$FIXTURE_ANDROID" ]; then
    subheading "  Fixture: expected_memory_batch1.json"
    echo ""

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
heading "4/4  What This Gives Us"
echo ""
echo "  The standalone pipeline is a verified reference implementation."
echo "  Every component is tested in isolation AND end-to-end."
echo ""
subheading "  Components:"
echo "    CSVDataProvider    — reads timestamped samples from CSV"
echo "    TimeseriesBatcher  — accumulates N samples, flushes when full"
echo "    TimeseriesEventBuilder — samples + config --> full RUM envelope"
echo "    TimeseriesEncoder  — event --> deterministic JSON"
echo "    TimeseriesPipeline — orchestrates the full flow"
echo ""
subheading "  Test coverage:"
echo "    iOS:     36 tests (byte-for-byte fixture match)"
echo "    Android: 36 tests (structural JSON comparison)"
echo ""
subheading "  Schema contract:"
echo "    _dd.format_version = 2"
echo "    type = \"timeseries\""
echo "    timeseries.name = memory_usage | cpu_usage"
echo "    Event date in ms, data point timestamps in ns"
echo "    Null fields omitted (service, version)"
pause

# ============================================================================
separator
heading "Next Steps"
echo ""
echo "    Complete the end-to-end pipeline:"
echo "      - Wire SDK business logic into the real iOS and Android SDKs"
echo "      - Connect to backend so we can test the full pipeline"
echo "        (SDK --> backend --> query)"
echo ""
echo "    Once the full pipeline works end-to-end:"
echo "      - Iterate on sampling rates, batching strategies, thresholds"
echo "      - Measure real session size impact"
echo "      - Tune based on backend query performance feedback"
separator
echo ""
narrate "  End of demo."
echo ""
