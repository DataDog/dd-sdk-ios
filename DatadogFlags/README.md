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

Subject authorization prevents the SDK from returning retained assignments for one subject while the app requests assignments for another subject. If your environment requires subject authorization, obtain a JWT for the subject from your backend and include it in the complete evaluation context update:

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

Your backend signs the token for the requested subject and environment. Keep the private key on your backend. Before the token expires, call `setEvaluationContext` again with the complete context and a new token. Changing only the token still triggers an assignment download. To remove the token, omit `dd_assignment_token` or set it to an empty string. The SDK does not restore an earlier token.

The SDK treats the JWT as opaque and sends it only in the `DD-Assignment-Token` request header. The assignment endpoint validates its signature, expiration, and other claims. The SDK removes `dd_assignment_token` from targeting attributes, disk snapshots, evaluation and exposure telemetry, RUM annotations, and SDK diagnostics. A custom flags header with the reserved name, in any letter case, is ignored so that the evaluation context remains the only credential source.

A usable token is a nonempty string containing only printable ASCII characters without whitespace (`0x21...0x7e`). Missing, `null`, empty, and unusable values send no header and do not establish a subject boundary by themselves. An unusable value produces a fixed warning that does not contain the supplied value. The assignment request still proceeds so that the endpoint can decide whether authorization is required.

A usable token creates a subject boundary as soon as the context update begins:

- Retained assignments for a different targeting key are unavailable while the download is in progress and after it fails. Evaluation returns the application default with `.general`.
- Retained assignments for the same targeting key remain eligible as a fallback. After a failed refresh, the client becomes stale and the assignments retain their original downloaded context for evaluation and telemetry.
- Experimentation opt-out modes continue to require their stricter full-context and policy match.

The same boundary is established when the endpoint returns HTTP 401 with a JSON:API `errors` entry whose `code` is exactly `ASSIGNMENT_AUTHORIZATION_FAILED`, even if no token was sent. Without eligible assignments, evaluations return the application default with `.general`. Removing the token or retrying does not restore another subject's retained assignments while this failure remains unresolved.

A successful download or eligible same-subject stale fallback recovers the client and ends this boundary, matching the browser provider. Without a usable token or an `ASSIGNMENT_AUTHORIZATION_FAILED` rejection, the SDK does not establish a boundary, and evaluation follows the ordinary iOS behavior. With experimentation opt-out disabled, previous assignments may remain available while a later download is pending; if the download fails, only an exact-context fallback is eligible. Applications using subject authorization should include the appropriate token in each complete context update that requires it. Overlapping requests still cannot install superseded authorization results after recovery.

Customer proxies must forward `DD-Assignment-Token`. Assignment requests follow HTTP redirects. Configure `customFlagsEndpoint` with its final HTTPS URL to avoid forwarding `DD-Assignment-Token` to a redirect destination. The SDK does not automatically refresh tokens, retry context updates, or verify signed assignment response payloads.

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
Before the first context update, evaluations return defaults with `providerNotReady`. During a valid context update or after a fetch failure,
evaluations without readable assignments return `general` when a subject-authorization boundary is active and `providerNotReady` otherwise.
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

## Evaluation telemetry privacy

Evaluation telemetry is protected by default. Each event sends the targeting key as `sha256_` followed by the lowercase hex SHA-256 of its UTF-8 bytes, and omits the evaluation context. An empty targeting key is sent as an empty string. With the default experimentation opt-out mode (`.disabled`), an evaluation made before a flags configuration is available sends its event with the targeting key omitted. With `.immediate` or `.futureExperimentsOnly`, an evaluation for a requested context whose configuration is still loading sends that context's targeting key in protected form. In both consent modes, the SDK omits a targeting key that fails strict UTF-8 encoding, such as one with an unpaired UTF-16 surrogate, and still counts the evaluation.

The raw targeting key and the evaluation context are sent only when the flags configuration for the evaluated context enables full evaluation data. The SDK keeps that setting with the configuration it applies to, including when the configuration is restored from disk. A refresh changes later evaluations only. Events that are waiting to be sent keep the setting that applied when the flag was evaluated.

Evaluation errors are reported only as `PROVIDER_NOT_READY`, `PROVIDER_FATAL`, `FLAG_NOT_FOUND`, `PARSE_ERROR`, `TYPE_MISMATCH`, `TARGETING_KEY_MISSING`, `INVALID_CONTEXT`, or `GENERAL`. Any other error is reported as `GENERAL`.

These rules apply to evaluation telemetry only. They do not change assignment requests, targeting, or exposure events. The [evaluation telemetry control](#evaluation-telemetry-control) still suppresses evaluation telemetry for opted-out subjects.

## Exposures in your own data store

Set `Flags.Configuration.exposureHook` to receive every flag evaluation, with the same exposure deduplication the SDK uses for Datadog. Set `trackExposures` to `false` to stop sending exposures to Datadog at the same time.

```swift
import DatadogFlags

var configuration = Flags.Configuration(trackExposures: false)
configuration.exposureHook = ExposureHook { evaluation in
    guard evaluation.shouldSend else {
        return
    }
    exposureQueue.enqueue(
        flag: evaluation.flagKey,
        variant: evaluation.variant,
        allocation: evaluation.allocationKey,
        subject: evaluation.targetingKey,
        holdoutKey: evaluation.features["holdout.key"]
    )
}
Flags.enable(with: configuration)
```

`ExposureEvaluation` has these members:

| Member | Meaning |
| --- | --- |
| `isExposure` | A successful evaluation of an allocation that logs exposures, repeats included. |
| `isCacheHit` | The subject was already exposed to the same flag, allocation, variant and split. |
| `shouldSend` | A new exposure (`isExposure` and a cache miss): exactly what the SDK sends to Datadog when `trackExposures` is `true`. |
| `features` | Features of the selected split for customer code, for example `holdout.key`, `holdout.assignment_group` and `holdout.should_include_in_holdout_analysis`. |
| `flagKey`, `variant`, `allocationKey`, `targetingKey`, `evaluationContext` | The evaluation. A failed evaluation has a `nil` `variant` and `allocationKey`. |

- The hook receives evaluations from every `FlagsClient` created after `Flags.enable(with:)`, including failed ones, which have `isExposure == false`. It also receives evaluations made through the OpenFeature provider, because the provider evaluates with a `FlagsClient`.
- The callback runs synchronously on the thread that evaluated the flag, including the main thread. Keep it short and move I/O to another queue.
- The SDK catches an error thrown by the callback and returns the evaluation result unchanged. It logs the first error as a warning and later errors at debug level.
- The hook is set once for the `Flags` feature, and each client keeps its own exposure cache. Two clients that evaluate the same flag for the same subject each report one exposure, to Datadog and to the hook.
- Each client deduplicates exposures in memory, for up to 5,000 subject and flag pairs. After the app restarts, the first evaluation of a flag is a new exposure.
- The SDK records an exposure when the flag resolves in the native client. OpenFeature Swift hooks are non-throwing, so the result that the provider returns is final. Inside an OpenFeature `MultiProvider`, the SDK records exposures for every evaluation of the Datadog provider. The built-in first-match and first-successful strategies use the Datadog result whenever it succeeds. A strategy that evaluates every provider and picks one, such as a comparison strategy, can make the SDK record an exposure for a result that the app discards.
- With `trackExposures` set to `false`, the SDK stops sending exposures to Datadog and keeps deduplicating them, so `isCacheHit` and `shouldSend` stay correct. Evaluation counts keep their usual behaviour.

`FlagDetails.flagMetadata` carries the same features as `__dd_feature.<key>` entries, for example `__dd_feature.holdout.key`. The `__dd_feature.` prefix is the stable contract.

## Usage attribution

Flag requests send the SDK's `service` in the `dd-service` header, so Usage Attribution can split Feature Flags usage by `service`. It is the same service RUM reports: the one set in `Datadog.Configuration`, or else the bundle identifier (or `ios` without one).
