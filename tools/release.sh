#!/bin/zsh

# Usage:
# ./tools/release.sh -h

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh
source ./tools/secrets/get-secret-aws.sh

# set_description "Deploys release --artifact for given --tag."
# define_arg "tag" "" "The tag to deploy artifact for (must be a tag that exists in remote)." "string" "true"
# define_arg "artifact" "" "The type of artifact to deploy" "string" "true"

DISTRIBUTION_PACKAGE="tools/distribution"

# echo_subtitle "Run 'make clean install' in '$DISTRIBUTION_PACKAGE'"
# cd $DISTRIBUTION_PACKAGE && make clean install
# cd -

# echo "TEST_SECRET='$TEST_SECRET'"

SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
get_secret "ssh.key" > $SSH_KEY_PATH
chmod 600 "$SSH_KEY_PATH"

cat <<EOF > "$HOME/.ssh/config"
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_KEY_PATH
    StrictHostKeyChecking no
EOF

set +e
set -x
ls -a ~/.ssh # custom
cat ~/.ssh/config # none

git clone --branch 2.12.0 --single-branch git@github.com:DataDog/dd-sdk-ios.git
