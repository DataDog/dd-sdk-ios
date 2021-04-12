#!/bin/bash

# Patches `sources.swiftlint.yml` and `tests.swiftlint.yml` configs for swiftlint `0.42.0`.
# We need to run this patch on Bitrise, as their brew-core mirror doesn't include swiftlint `0.43.1` 
# on some agent versions (notably: `Agent version:	1.20.0` considers `0.42.0` as the latest version).
# 
# REF: we could eventually switch to the official brew source, but this is discouraged in 
# https://discuss.bitrise.io/t/how-to-change-brew-core-from-mirror-to-official/16033

SWIFTLINT_VERSION=$(swiftlint version)

if [ $SWIFTLINT_VERSION = "0.42.0" ]; then
	echo "⚙️ Found swiftlint '0.42.0', applying the patch."
	# Replace "../../" with ""
	sed -i '' 's/..\/..\///g' tools/lint/sources.swiftlint.yml
	sed -i '' 's/..\/..\///g' tools/lint/tests.swiftlint.yml
else
	echo "⚙️ Using swiftlint '${SWIFTLINT_VERSION}', no need to patch."
fi
