#!/bin/zsh

source ./tools/utils/echo_color.sh

# Usage:
#   get_secret <secret_name>
#
# Notes:
#   - This function requires AWS CLI to be configured properly with access to the SSM Parameter Store.
get_secret() {
    local secret_name="ci.dd-sdk-ios.$1"
    local secret_value=$(aws ssm get-parameter --region us-east-1 --name $secret_name --with-decryption --query "Parameter.Value" --out text)

    if [[ -z "$secret_value" ]]; then
        echo_err "Error" "Failed to retrieve the '$secret_name' secret or the secret is empty."
        return 1
    fi

    echo $secret_value
}
