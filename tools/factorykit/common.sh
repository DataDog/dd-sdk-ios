#!/bin/zsh

# Shared settings for the FactoryKit scripts in tools/factorykit.
# FactoryKit runs the documentation gate (scripts/foundation_check.py).
# The runtime lives outside the repository and is keyed by the pinned commit,
# so bumping FACTORYKIT_SHA installs a fresh runtime next to the old one.

FACTORYKIT_SHA="2aee46c4733de5ff7d2ff91c3ed34a13395869a9"
FACTORYKIT_RUNTIME="${XDG_CACHE_HOME:-$HOME/.cache}/dd-sdk-ios/factorykit/$FACTORYKIT_SHA"
