#!/bin/zsh

# Checks if all secret values are available in current env.
#
# Usage:
# $ ./tools/secrets/check-secrets.sh
#
# Note:
# - Requires `vault` to be installed

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/secrets/get-secret.sh

echo_subtitle "Check if secret values are available"

for key in ${(k)DD_IOS_SECRETS}; do
    secret_name=${DD_IOS_SECRETS[$key]%% |*}
    get_secret $secret_name > /dev/null && echo_succ "$secret_name - OK"
done
