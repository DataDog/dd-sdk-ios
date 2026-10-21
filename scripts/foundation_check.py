from factorykit.document_checks import foundation_entry

foundation_entry(
    entry_documents=("AGENTS.md",),
    document_indexes=("docs/README.md",),
    check_extensions=(("factory.literate_extension", "selected_literate_check"),),
    nudge_extensions=(
        ("factorykit.foundation_nudges", "baseline_nudges"),
        ("factory.literate_extension", "selected_literate_nudge"),
    ),
)
