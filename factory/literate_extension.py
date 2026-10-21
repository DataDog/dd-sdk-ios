# Literate selection for the FactoryKit Foundation entry.
#
# This wrapper names the living designs, contributor guides, and the document
# map that routes readers to them. The Foundation gate blocks when a selected
# document is missing or the map does not link to it. The SDK source is Swift
# and Objective-C, so no Python code narrative is selected.
# Link: <../docs/README.md>
from factorykit.literate import literate_checks, literate_nudges


def selected_literate_check(context):
    return literate_checks(
        context,
        design_paths=(
            "docs/ARCHITECTURE.md",
            "DatadogRUM/RUM_FEATURE.md",
            "DatadogSessionReplay/SESSION_REPLAY_FEATURE.md",
            "DatadogTrace/TRACE_FEATURE.md",
            "DatadogProfiling/PROFILING_FEATURE.md",
            "DatadogLogs/LOGS_FEATURE.md",
        ),
        user_guide_paths=(
            "docs/DEVELOPMENT.md",
            "docs/TESTING.md",
        ),
        navigation_paths=("docs/README.md",),
        source_paths=(),
    )


def selected_literate_nudge(context):
    return literate_nudges(context)
