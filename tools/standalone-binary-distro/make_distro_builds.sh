#!/bin/zsh

gh auth status;
if [[ $? != 0 ]]; then
  exit 1
fi

SDK_VERSION=$(git describe --exact-match --tags)
if [[ $? != 0 ]]; then
  echo "❌ Aborting: HEAD doesn't have a tag!"  
  exit 2
elif [[ `git status --porcelain` ]]; then
  echo "❌ Aborting: Working directory has changes!"
  exit 3
elif [ ! -f "Cartfile" ]; then
	echo "❌ Aborting: \`make_distro_builds.sh\` must be run from the same place with `Cartfile`"
  exit 4
fi
OUT_FILENAME="Datadog-$SDK_VERSION.zip"

# create temporary xcconfig for carthage build
set -euo pipefail
xcconfig=$(mktemp /tmp/static.xcconfig.XXXXXX)
# carthage may try to build schemes in dependency-manager-tests folder, so we hide it temporarily
mv dependency-manager-tests/ .dependency-manager-tests/
trap 'rm -f "$xcconfig" ; mv .dependency-manager-tests/ dependency-manager-tests/ ;' INT TERM HUP EXIT
echo "BUILD_LIBRARY_FOR_DISTRIBUTION = YES" >> $xcconfig
export XCODE_XCCONFIG_FILE="$xcconfig"

# clear existing carthage artifacts
rm -rf Carthage/

# fetch 3rd party deps via carthage
echo "carthage bootstrap with no build..."
carthage bootstrap --no-build

echo "carthage build..."
carthage build --platform iOS --use-xcframeworks --no-skip-current
# reset trap
trap - INT TERM HUP EXIT
rm -f "$xcconfig"; mv .dependency-manager-tests/ dependency-manager-tests/ ;

# zip artifacts
cd Carthage/Build/
zip --symlinks -r $OUT_FILENAME *.xcframework

# upload zip
gh release upload $SDK_VERSION $OUT_FILENAME -R DataDog/dd-sdk-ios
