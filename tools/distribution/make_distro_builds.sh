#!/bin/zsh

gh auth status;
if [[ $? != 0 ]]; then
  exit 1
fi

SDK_VERSION="${BITRISE_GIT_TAG:=$(git describe --exact-match --tags)}"
if [[ -z $SDK_VERSION ]]; then
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
export XCODE_XCCONFIG_FILE="$xcconfig"

# Prepares the repository folder for building xcframeworks.
prepare() {
   echo "BUILD_LIBRARY_FOR_DISTRIBUTION = YES" >> $xcconfig
   # carthage may try to build schemes in dependency-manager-tests folder, so we hide it temporarily
   mv dependency-manager-tests/ .dependency-manager-tests/ 
   # hide '*.local.xcconfigs' so they are not applied to produced artifacts (they are renamed to '*_bak'):
   find . -type f -name '*.local.xcconfig' -exec mv '{}' '{}_bak' ';'
   rm -rf Carthage/
}

# Resets repository changes made in 'prepare()'
cleanup() {
   rm -f "$xcconfig"
   mv .dependency-manager-tests/ dependency-manager-tests/
   # revert hidding '*.local.xcconfigs' (rename back from '*_bak'):
   find . -type f -name '*.local.xcconfig_bak' | sed -e 'p;s/_bak//' | xargs -n2 mv 
}

build_xcframeworks() {
   trap cleanup INT TERM HUP EXIT
   echo "carthage bootstrap with no build..."
   carthage bootstrap --no-build
   echo "carthage build..."
   carthage build --platform iOS --use-xcframeworks --no-skip-current
   trap - INT TERM HUP EXIT
}

prepare
build_xcframeworks
cleanup

# zip artifacts
cd Carthage/Build/

zip --symlinks -r $OUT_FILENAME *.xcframework

# upload zip
gh release upload $SDK_VERSION $OUT_FILENAME -R DataDog/dd-sdk-ios
