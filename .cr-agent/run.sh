#!/usr/bin/env bash
# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------
#
# Entry point for the `Code Review` CI job.
# Clones rum-ai-toolkit over HTTPS using a short-lived dd-octo-sts token,
# mints a second dd-octo-sts token for posting PR comments, then hands off
# to the toolkit's `review.sh` which runs the `cr-agent`.

set -eo pipefail

# TODO: switch toolkit ref to `main` before merging to develop.
TOOLKIT_REF="ncreated/feat/cr-agent"
# TODO: remove before merging — force re-review for e2e testing.
export CR_AGENT_FORCE_REVIEW=1
TOOLKIT_DIR="$CI_PROJECT_DIR/.rum-ai-toolkit"

echo "▸ Minting rum-ai-toolkit clone token via dd-octo-sts..."
TOOLKIT_TOKEN=$(dd-octo-sts --disable-tracing token \
    --scope DataDog/rum-ai-toolkit --policy dd-sdk-ios.gitlab.clone)

echo "▸ Cloning rum-ai-toolkit ($TOOLKIT_REF)..."
git clone --depth 1 --branch "$TOOLKIT_REF" \
    "https://x-access-token:${TOOLKIT_TOKEN}@github.com/DataDog/rum-ai-toolkit.git" "$TOOLKIT_DIR"

# Clone token no longer needed after clone; revoke it explicitly (least privilege).
dd-octo-sts --disable-tracing revoke -t "$TOOLKIT_TOKEN"

echo "▸ Installing cr-agent venv..."
make -C "$TOOLKIT_DIR/tools/cr-agent" install

echo "▸ Minting GitHub token via dd-octo-sts (policy: self.cr-agent)..."
GITHUB_TOKEN=$(dd-octo-sts --disable-tracing token --scope DataDog/dd-sdk-ios --policy self.cr-agent)
export GITHUB_TOKEN
trap 'dd-octo-sts --disable-tracing revoke -t "$GITHUB_TOKEN"' EXIT

echo "▸ Handing off to review.sh..."
exec "$TOOLKIT_DIR/tools/cr-agent/review.sh"
