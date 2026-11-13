# Datadog Flags

## Evaluation telemetry control

Enable the evaluation telemetry control when creating a Flags client:

```swift
Flags.enable()
let client = FlagsClient.create(
    configuration: .init(enableEvaluationTelemetryOptOutParameter: true)
)

client.setEvaluationContext(
    FlagsEvaluationContext(
        targetingKey: "user-123",
        attributes: ["dd_evaluation_telemetry_opt_out": .bool(true)]
    )
)
```

The option defaults to `false`. When enabled and the context is known, only a typed boolean `true` suppresses new evaluation events, evaluation counts, and automatic RUM flag annotations. Missing, false, null, numeric, and string values do not suppress them.

Telemetry suppression does not change flag evaluation, exposure logging, or unrelated telemetry. It does not remove events or annotations recorded before the update.

The attribute remains available in assignment requests, stored context, and exposure attributes. Applications can use it in targeting rules. Changes use the normal assignment refresh and exposure deduplication behavior. A targeting rule can therefore change an assignment when this attribute changes.

The latest requested context controls telemetry suppression immediately, including while an assignment refresh is pending or fails. Before the first context update, cached context controls suppression. When the option is enabled, evaluation telemetry is suppressed while that initial cache read is pending because its policy is not yet known. Reporting resumes if the read finds no opt-out or an explicitly supplied context allows it. The client configuration still determines whether suppression is enabled.

Each client keeps its own configuration and current policy. If a client name already exists, `create` returns that client and keeps its original configuration.

This option controls evaluation telemetry only. Exposure events can still contain subject data. It does not replace the SDK tracking-consent API.

## Subject authorization for assignment downloads

For an environment configured to require subject authorization, obtain a JWT from your backend and include it in the complete evaluation context update:

```swift
client.setEvaluationContext(
    FlagsEvaluationContext(
        targetingKey: "user-123",
        attributes: [
            "country": .string("US"),
            "dd_assignment_token": .string(jwtFromYourBackend)
        ]
    )
)
```

Your backend signs the token for the requested subject and environment. Keep the private key on your backend and replace the token before it expires. The SDK treats the JWT as opaque and sends it in the `DD-Assignment-Token` request header; the assignment endpoint validates its signature, expiration, and claims. The reserved `dd_assignment_token` field is removed from targeting attributes, disk snapshots, evaluation and exposure telemetry, RUM annotations, and SDK diagnostics. A custom flags header with the reserved name, in any letter case, is ignored so that the evaluation context remains the only credential source.

Missing, `null`, and empty-string token values send no header. Other types, or strings containing whitespace or non-ASCII characters, also send no header and produce a fixed warning that does not contain the supplied value. The assignment request still proceeds so that the endpoint can decide whether authorization is required. An unusable replacement never restores a previous token or a custom reserved header.

Assignment requests carrying a token refuse all HTTP redirects, including redirects within the same origin. The redirect destination receives no request or token. A refused redirect is handled as an ordinary download failure and can use an eligible stale fallback. Requests without a usable token retain their existing redirect behavior.

A usable token creates a subject boundary as soon as the context update begins. Assignments for a different targeting key are withheld while the request is pending and after failure. Existing assignments for the same targeting key can remain available; after a failed refresh they are reported as stale and retain the original downloaded context for evaluation and telemetry. Experimentation opt-out modes continue to require their stricter full-context and policy match.

The same boundary is established when the endpoint returns HTTP 401 with a JSON:API `errors` entry whose `code` is exactly `ASSIGNMENT_AUTHORIZATION_FAILED`, even if no token was sent. Without eligible assignments, evaluations return the application default with `general`. Removing the token or retrying does not restore another subject's retained assignments while this failure remains unresolved.

A successful download or eligible same-subject stale fallback recovers the client and ends this boundary, matching the browser provider. A later context update without a usable token follows the existing iOS behavior: with experimentation opt-out disabled, previous assignments may remain available while the download is pending; if the download fails, only an exact-context fallback is eligible. Applications using subject authorization should include the appropriate token in each complete context update that requires it. Overlapping requests still cannot install superseded authorization results after recovery.

Customer proxies must forward `DD-Assignment-Token`. This release does not verify signed assignment response payloads.

## Per-subject experimentation opt-out

Select an opt-out mode in `FlagsClient.Configuration` when creating the client. The default is disabled.
The application owns the subject's preference and timestamp.

```swift
import DatadogFlags

// Initialize Datadog and enable Flags before creating the client.
let client = FlagsClient.create(configuration: .init(experimentationOptOutMode: .immediate))

// Omit this attribute when the subject can participate in experimentation.
let context = FlagsEvaluationContext(
    targetingKey: "subject-123",
    attributes: [
        "dd_experimentation_opt_out_at": .string("2026-10-21T12:00:00Z")
    ]
)
client.setEvaluationContext(context) { result in
    switch result {
    case .success:
        let enabled = client.getBooleanValue(key: "new-route-planner", defaultValue: false)
        // Use the assigned ordinary feature value.
    case .failure:
        // Evaluations use the application's defaults when no valid assignments exist.
        break
    }
}
```

| Mode | Behavior when the subject has an opt-out timestamp |
| --- | --- |
| `.disabled` | Ignore the timestamp. |
| `.immediate` | Skip all experiment allocations, including experiments already in progress. |
| `.futureExperimentsOnly` | Skip experiment allocations activated at or after the timestamp, or with an unknown activation time. |

Both enabled modes use the same customer-owned timestamp, in the supported RFC3339 subset below.
In `.immediate` mode, any valid timestamp excludes the subject now, including a future timestamp.
In `.futureExperimentsOnly` mode, a future timestamp keeps allocations activated before that timestamp available.
Supply the actual opt-out time to exclude allocations activated from that time onward.
Use a full `YYYY-MM-DDTHH:mm:ss` date and time, followed by `Z` or a numeric `+HH:mm` or `-HH:mm` offset.
`T` and `Z` may be lowercase. An optional decimal fraction is preserved to nanosecond precision;
additional digits are truncated without rounding. Dates use the proleptic Gregorian calendar,
including year `0000`; both the written date and normalized UTC instant must have years `0000`–`9999`.
Whitespace, leap seconds, named timezones, and invalid calendar fields are rejected.
Acknowledgement timestamps follow the same format and compare the normalized instant.
The Precompute service continues through remaining allocations. If none match, evaluation returns the application's default value.
Future-experiments-only mode leaves older allocations available. It does not prove prior enrollment or preserve a previous assignment.

Malformed strings, nulls, and non-string values return `invalidContext` without making a request.
The SDK does not guess the subject's preference. Disabled mode ignores the attribute.

The Precompute service must acknowledge experimentation opt-out before the client accepts its assignments.
Future mode requires the same mode and cutoff instant, compared at nanosecond precision.
When no opt-out applies, the client rejects responses containing an opt-out mode or cutoff, or a true opt-out acknowledgement.
An unsupported service cannot silently return experimental assignments. The SDK uses only cached assignments
that match the current context and opt-out policy. Otherwise it returns application defaults.
A missing acknowledgement reports `invalidResponse` through the context completion and sets the client to `error` when no matching cache exists.
A later `setEvaluationContext` call can fetch assignments again.

With either enabled mode, context isolation also applies when the timestamp attribute is absent.
Before the first context update, and while a different context is pending, evaluations return defaults with `providerNotReady`.
A malformed timestamp returns `invalidContext`. Disabled mode keeps previous assignments available while a refresh is pending.
An invalid context does not overwrite or delete the last successful disk snapshot.
Snapshots with an opt-out policy use cache version 3. Older SDKs that support only versions 1 or 2 cannot restore them.
The current SDK still reads unfiltered snapshots in versions 1 and 2. Filtered snapshots from earlier development builds using those versions are rejected.

Experimentation opt-out does not disable evaluation telemetry or RUM flag annotations.
With either enabled mode, pending, failed, and invalid contexts retain the requested subject identity in evaluation telemetry.
The independent [`enableEvaluationTelemetryOptOutParameter`](#evaluation-telemetry-control) option can suppress that telemetry without changing assignments or exposures. Excluded experiment allocations do not produce exposures.
Older allocations retained by future mode still produce their normal exposures. No withdrawal event is added.
Immediate withdrawal can change an enrolled subject's experience. Account for that change in experiment analysis.

Client configuration is fixed for each client name. Creating a client with an existing name returns the existing client, which keeps its original configuration.
