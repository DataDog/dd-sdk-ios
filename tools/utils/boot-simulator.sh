#!/bin/zsh

# Usage:
# $ source ./tools/utils/boot-simulator.sh
# $ boot_simulator_in_background "<platform>" "<os>" "<device>"
#
# Starts booting the simulator that matches an xcodebuild destination, e.g. 'iOS Simulator', '26.5', 'iPhone 17 Pro',
# and returns without waiting. xcodebuild then finds the simulator booted, or booting, when it gets to testing.
# It does nothing for macOS or when no simulator matches.

boot_simulator_in_background() {
    local platform="$1"
    local os="$2"
    local device="$3"

    [[ "$platform" == *" Simulator" ]] || return 0

    local udid
    if ! udid=$(./tools/utils/find-simulator.py --platform "$platform" --os "$os" --device "$device"); then
        echo "No '$device' simulator found for '$platform' '$os', xcodebuild will boot one."
        return 0
    fi

    echo "Booting '$device' simulator ($udid) in the background."
    xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 &!
}
