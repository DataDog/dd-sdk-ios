#!/bin/zsh

# Usage:
# ./tools/release.sh -h

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Deploys release --artifact for given --tag."
define_arg "tag" "" "The tag to deploy artifact for (must be a tag that exists in remote)." "string" "true"
define_arg "artifact" "" "The type of artifact to deploy" "string" "true"

DISTRIBUTION_PACKAGE="tools/distribution"

echo_subtitle "Run 'make clean install' in '$DISTRIBUTION_PACKAGE'"
cd $DISTRIBUTION_PACKAGE && make clean install
cd -


