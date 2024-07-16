#!/bin/zsh

DD_VAULT_ADDR=https://vault.us1.ddbuild.io

# The common path prefix for all dd-sdk-ios secrets in Vault.
#
# When using `vault kv put` to write secrets to a specific path, Vault overwrites the entire set of secrets
# at that path with the new data. This means that any existing secrets at that path are replaced by the new
# secrets. For simplicity, we store each secret independently by writing each to a unique path.
DD_IOS_SECRETS_PATH_PREFIX='kv/aws/arn:aws:iam::486234852809:role/ci-dd-sdk-ios/'

# Full description of secrets is available at https://datadoghq.atlassian.net/wiki/x/cIEB4w (internal)
# Keep this list and Confluence page up-to-date with every secret that is added to the list.
DD_IOS_SECRET__TEST_SECRET="test.secret"
DD_IOS_SECRET__GH_CLI_TOKEN="gh.cli.token"
DD_IOS_SECRET__CP_TRUNK_TOKEN="cocoapods.trunk.token"
DD_IOS_SECRET__SSH_KEY="ssh.key"
DD_IOS_SECRET__E2E_CERTIFICATE_P12_BASE64="e2e.certificate.p12.base64"
DD_IOS_SECRET__E2E_CERTIFICATE_P12_PASSWORD="e2e.certificate.p12.password"
DD_IOS_SECRET__E2E_PROVISIONING_PROFILE_BASE64="e2e.provisioning.profile.base64"
DD_IOS_SECRET__E2E_XCCONFIG_BASE64="e2e.xcconfig.base64"
DD_IOS_SECRET__E2E_S8S_API_KEY="e2e.s8s.api.key"
DD_IOS_SECRET__E2E_S8S_APP_KEY="e2e.s8s.app.key"
DD_IOS_SECRET__E2E_S8S_APPLICATION_ID="e2e.s8s.app.id"

declare -A DD_IOS_SECRETS=(
    [0]="$DD_IOS_SECRET__TEST_SECRET | test secret to see if things work, free to change but not delete"
    [1]="$DD_IOS_SECRET__GH_CLI_TOKEN | GitHub token to authenticate 'gh' cli (https://cli.github.com/)"
    [2]="$DD_IOS_SECRET__CP_TRUNK_TOKEN | Cocoapods token to authenticate 'pod trunk' operations (https://guides.cocoapods.org/terminal/commands.html)"
    [3]="$DD_IOS_SECRET__SSH_KEY | SSH key to authenticate 'git clone git@github.com:...' operations"
    [4]="$DD_IOS_SECRET__E2E_CERTIFICATE_P12_BASE64 | Base64-encoded '.p12' certificate file for signing E2E app"
    [5]="$DD_IOS_SECRET__E2E_CERTIFICATE_P12_PASSWORD | Password to '$DD_IOS_SECRET__E2E_CERTIFICATE_P12_BASE64' certificate"
    [6]="$DD_IOS_SECRET__E2E_PROVISIONING_PROFILE_BASE64 | Base64-encoded provisioning profile file for signing E2E app"
    [7]="$DD_IOS_SECRET__E2E_XCCONFIG_BASE64 | Base64-encoded xcconfig file for E2E app"
    [8]="$DD_IOS_SECRET__E2E_S8S_API_KEY | DATADOG_API_KEY for uploading E2E app to synthetics"
    [9]="$DD_IOS_SECRET__E2E_S8S_APP_KEY | DATADOG_APP_KEY for uploading E2E app to synthetics"
    [10]="$DD_IOS_SECRET__E2E_S8S_APPLICATION_ID | Synthetics app ID for E2E tests"
)
