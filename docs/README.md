# Documentation map

Use this map to find the current documentation for the Datadog SDK for iOS and
tvOS. Read the [repository instructions](../AGENTS.md) before you change the
repository. The rows below are the current authority for each topic.

## SDK-wide documentation

| Need | Document |
| --- | --- |
| Understand the SDK principles | [SDK philosophy](../ZEN.md) |
| Understand modules, data flow, and key abstractions | [Architecture](ARCHITECTURE.md) |
| Add a feature, a command, or a context provider | [Development recipes](DEVELOPMENT.md) |
| Write or fix tests and use the mock infrastructure | [Testing](TESTING.md) |
| Apply naming, lint, file header, and commit rules | [Conventions](CONVENTIONS.md) |
| Report errors safely to customers and to internal telemetry | [Error handling](ERROR_HANDLING.md) |
| Change a fragile area | [Known concerns](KNOWN_CONCERNS.md) |
| Write or change a swizzle | [Swizzling](SWIZZLING.md) |
| Contribute to the project | [Contribution guidelines](../CONTRIBUTING.md) |
| Examine documentation links before a commit or a pull request | [Documentation gate](DEVELOPMENT.md#documentation-gate) |

## Feature documentation

Each feature module has a design document at its root. Use the
[feature documentation guidelines](LLM_FEATURE_DOCS_GUIDELINES.md) when you
update one of these documents.

| Feature | Document |
| --- | --- |
| RUM | [RUM feature](../DatadogRUM/RUM_FEATURE.md) |
| Session Replay | [Session Replay feature](../DatadogSessionReplay/SESSION_REPLAY_FEATURE.md) |
| Trace (APM) | [Trace feature](../DatadogTrace/TRACE_FEATURE.md) |
| Profiling | [Profiling feature](../DatadogProfiling/PROFILING_FEATURE.md) |
| Logs | [Logs feature](../DatadogLogs/LOGS_FEATURE.md) |

## Performance

| Need | Document |
| --- | --- |
| Read the SDK performance benchmarks | [SDK performance](sdk_performance.md) |
| Read the Session Replay performance benchmarks | [Session Replay performance](session_replay_performance.md) |

## Proposals

Major changes need an internal RFC. RFCs are not stored in this repository.
The [RFC process](DEVELOPMENT.md#rfc-process-for-major-changes) tells you when
an RFC is necessary.
