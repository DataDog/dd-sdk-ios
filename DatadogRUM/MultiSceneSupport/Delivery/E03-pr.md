# Preserve Resource completion ownership and failed-transfer errors

A request that finishes after navigation or a session change can update another view's live action counters. A URLSession transfer that receives headers and then fails can also be recorded as a completed Resource. This change resolves the tracked owner before dispatch and reports failed transfers as one owning network Error, retaining the received HTTP status.

Current-action behavior within the owning view, successful bodies, empty HEAD/204 responses and existing manual compatibility remain unchanged. The implementation stores only command-scoped owner identifiers.

Local validation: 925 RUM cases / 961 passing executions, nine passing native URLSession XCTest cases, and strict callback/serialized ownership assertions. The native audit explicitly classifies a source-proven inherited stopped-session precondition diagnostic; its original rejection and raw telemetry are preserved. Core passes815 cases with exactly four predefined OS skips. Twelve affected-platform Debug/Release builds, changed-file lint and affected RUM documentation checks pass.

This packet is not ready for publication. Nine remaining iOS suites, inherited global Trace-document drift, a real ticket, current CI and human review remain. No backend ingestion or complete session-metadata correctness is claimed.
