# Multi-scene source backup

This branch preserves SDK and test-harness source for the multi-scene project.
It is a source backup, not a release candidate or an approval to merge.
Delivery branches retain their separate review, API, CI and release requirements.

Private research history, local configuration, backend exports and captured
acceptance evidence are excluded. The original evidence remains local.
Four historical replay test files and the probe's historical-results README are
also excluded because they depend on private local evidence. Real RUM application
IDs in four harness files have been replaced with the all-zero dummy UUID.
Configure a suitable application ID before using those fixtures with a backend.

The signed delivery branches preserve their original source trees. This broader
backup contains the explicit sanitization above and grants no runtime credit.
