# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

# Literate selection for the FactoryKit Foundation entry.
#
# This wrapper names the living designs, contributor guides, and the document
# map that routes readers to them. The Foundation gate blocks when a selected
# document is missing or the map does not link to it. The SDK source is Swift
# and Objective-C, so no Python code narrative is selected.
#
# Feature docs are discovered with the same rule as tools/feature-docs-verify.sh:
# every tracked *_FEATURE.md outside generated or vendored directories. A new
# feature doc is selected without a change here, and the gate then requires a
# route to it from the document map.
# Link: <../docs/README.md>
from factorykit.literate import literate_checks, literate_nudges

# Keep in sync with `ignored_dirs` in tools/feature-docs-verify.sh.
_IGNORED_DIRS = {".build", ".claude", ".git", "artifacts", "build", "Carthage", "Checkouts", "DerivedData"}


def _feature_docs(context):
    return tuple(sorted(
        path for path in context.view.paths
        if path.endswith("_FEATURE.md") and not _IGNORED_DIRS.intersection(path.split("/")[:-1])
    ))


def selected_literate_check(context):
    return literate_checks(
        context,
        design_paths=("docs/ARCHITECTURE.md", *_feature_docs(context)),
        user_guide_paths=(
            "docs/DEVELOPMENT.md",
            "docs/TESTING.md",
        ),
        navigation_paths=("docs/README.md",),
        source_paths=(),
    )


def selected_literate_nudge(context):
    return literate_nudges(context)
