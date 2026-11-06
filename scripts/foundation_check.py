# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

from factorykit.document_checks import foundation_entry

foundation_entry(
    entry_documents=("AGENTS.md",),
    document_indexes=("docs/README.md",),
    check_extensions=(),
    nudge_extensions=(("factorykit.foundation_nudges", "baseline_nudges"),),
)
