# Preserve Resource completion ownership and failed-transfer errors

A request that finishes after navigation or a session change can update another view's live action counters. A URLSession transfer that receives headers and then fails can also be recorded as a completed Resource. This change resolves the tracked owner before dispatch and reports failed transfers as one owning network Error, retaining the received HTTP status.

Current-action behavior within the owning view, successful bodies, empty HEAD/204 responses and existing manual compatibility remain unchanged. The implementation stores only command-scoped owner identifiers.

Local validation: 925 RUM cases / 961 passing executions and nine passing native URLSession cases qualify the ownership contract. Twelve platform builds pass. The eleven iOS schemes were exercised: nine strict audits pass, including full Integration287/287 on a test-only hitch-assertion composition; CrashReporting has66 qualified iOS assertions and one watchOS-only case. The original audits remain preserved.

The original Replay content-fixture failure is preserved and outside this change’s validation scope; no capture repair is included. Host-app crash safety and other-feature compatibility remain required. All five feature-document checks pass. The native stopped-session diagnostic, nine Integration QoS warnings matching prior evidence, real ticket, current CI and human review remain explicit. No backend ingestion or complete session-metadata correctness is claimed.
