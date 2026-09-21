# Preserve Resource completion ownership and failed-transfer errors

A request that finishes after navigation or a session change can update another view's live action counters. A URLSession transfer that receives headers and then fails can also be recorded as a completed Resource. This change resolves the tracked owner before dispatch and reports failed transfers as one owning network Error, retaining the received HTTP status.

Current-action behavior within the owning view, successful bodies, empty HEAD/204 responses and existing manual compatibility remain unchanged. The implementation stores only command-scoped owner identifiers.

Local validation: 925 RUM cases / 961 passing executions and nine passing native URLSession cases qualify the ownership contract. Twelve platform builds pass. The eleven iOS schemes were exercised: nine strict audits pass, including full Integration287/287 on a test-only hitch-assertion composition; CrashReporting has66 qualified iOS assertions and one watchOS-only case. The original audits remain preserved.

Full Replay remains unqualified:742 executions pass, three predefined reflection fixtures skip, and one scroll-pocket fixture fails identically on unchanged develop. A maintainer-owned fixture correction or explicit waiver is required. The native stopped-session diagnostic, nine Integration QoS warnings matching prior evidence, inherited Trace-document drift, real ticket, current CI and human review remain explicit. No backend ingestion or complete session-metadata correctness is claimed.
