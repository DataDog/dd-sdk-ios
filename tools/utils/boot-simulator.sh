#!/bin/zsh

# Usage:
# $ source ./tools/utils/boot-simulator.sh
# $ boot_simulator_in_background "<platform>" "<os>" "<device>"
#
# Starts booting the simulator that matches an xcodebuild destination, e.g. 'iOS Simulator', '26.5', 'iPhone 17 Pro',
# and returns without waiting. xcodebuild then finds the simulator booted, or booting, when it gets to testing.
# OS 'latest' picks the newest runtime of the platform. It does nothing for macOS or when no simulator matches.

boot_simulator_in_background() {
    local platform="$1"
    local os="$2"
    local device="$3"

    [[ "$platform" == *" Simulator" ]] || return 0

    local udid=$(xcrun simctl list -j | python3 -I -c '
import json, sys
platform, os_version, device = sys.argv[1:4]
platform = {"visionOS": "xrOS"}.get(platform, platform)
version_key = lambda r: [int(p) for p in r["version"].split(".")]
data = json.load(sys.stdin)
runtimes = [r for r in data["runtimes"] if r.get("isAvailable") and r.get("platform") == platform]
if os_version != "latest":
    runtimes = [r for r in runtimes if r["version"] == os_version or r["version"].startswith(os_version + ".")]
for runtime in sorted(runtimes, key=version_key, reverse=True):
    for d in data["devices"].get(runtime["identifier"], []):
        if d.get("isAvailable") and d["name"] == device:
            print(d["udid"])
            sys.exit(0)
' "${platform% Simulator}" "$os" "$device")

    if [[ -z "$udid" ]]; then
        echo "No '$device' simulator found for '$platform' '$os', xcodebuild will boot one."
        return 0
    fi

    echo "Booting '$device' simulator ($udid) in the background."
    xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 &!
}
