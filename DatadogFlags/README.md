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


# Assignment response signing (draft)

Signing-enabled requests set `X-stream: false` because whole-body proofs require buffered delivery.
Both observe and required modes apply this override. Signing-off requests keep their ordinary transport selection.

The first public response-signing protocol is v1. The SDK advertises `response-signing-v1`, sends signature version `1`, and verifies the `datadog.feature-flags.precomputed-assignments.v1` transcript. Earlier POC v1/v2 and draft v3 labels are not supported public versions; public v1 does not accept their proofs. X.509 v3 certificate encoding is unchanged.

Response signing is disabled by default. This draft enables a staging-only mobile pilot using the same public root as the browser SDK. Production endpoints have no bundled root. Signing protects response integrity; subject authorization remains separate.

```swift
Flags.enable(with: .init(
    customFlagsEndpoint: URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"),
    responseSigning: .init(mode: .required)
))
```

The bundled root applies only to `https://preview.ff-cdn.datad0g.com` on port 443.
The effective request endpoint selects trust, including a custom endpoint. The application's `env` value does not select a root.
A nonempty `trustedRootCertificates` list replaces bundled trust. No roots are downloaded.
Use required mode for the staging pilot; keep production signing off. Fresh sessions provide observations across rotations without adding polling.

`observe` attempts verification and records a bounded outcome, then accepts otherwise-valid responses when proof is absent, invalid or expired. Authentication, HTTP, redirect and JSON errors retain their ordinary failure behavior. Observation data uses a separate cache namespace hashed from the effective token, endpoint/query, environment, app ID, custom headers, mode and root pins; it never becomes a verified cache entry. The SDK waits for the current core scope before reading that namespace and never promotes client-name-only legacy data. A separately retained verified response remains available for same-context failure fallback until its original expiry.

`required` accepts only a complete, valid public v1 response with a leaf/intermediate chain under the endpoint-specific or explicitly configured root. It never retries an unsigned request. Verified fallback is memory-only, tied to this feature instance, the complete current request configuration scope and the exact evaluation context, and expires at the original signed deadline (at most five minutes). No disk entry is trusted or written in this mode; evaluation returns defaults after expiry, a context change without a fresh response, or restart. Core context messages invalidate the old scope before further reads; reset, scope changes and superseded requests cannot restore old assignments. Stopping the SDK releases a feature-owned lifetime guard, permanently invalidating signing on retained clients and fetchers. Pending responses and later context messages cannot reactivate that instance. Configure the mode and roots when enabling Flags; replace the feature instance through the ordinary SDK lifecycle to change trust configuration.

The staging root remains fixed while responses carry the current leaf and intermediate certificates. Routine certificate rotation does not require an SDK update or a record of earlier rotations. Root validity still bounds support for unchanged SDKs. The restricted DER parser enforces the certificate profile and does not fetch issuer certificates, system roots, AIA or OCSP.

Signing-enabled requests reject redirects, use a fresh 16-byte nonce and bind the exact emitted URL/query, request body, effective client token, semantic headers, response bytes and complete public chain. Verification runs before JSON decoding and cache admission, with expiry checked again at admission and evaluation. Response verification is bounded to 2 MiB and request signing to 1 MiB. Responses are buffered application bytes after HTTP decompression; this draft does not add a signed streaming or critical-flags protocol.

Disabling edge signing cannot weaken `required` in an installed SDK. A required client uses verified memory only until its signed expiry, then returns defaults. Restore valid signed delivery to recover. Mobile rotation and application lifecycle validation remain required before rollout beyond staging.

## Validation and shared fixtures

`Tests/Client/ResponseSigningCorpus.json` is copied byte-for-byte from the [shared public v1 corpus](https://github.com/DataDog/ffe-system-test-data/blob/b57eac6711204a906f0b24e127124a03314e35a9/response-signing/v1/corpus.json) at `b57eac6711204a906f0b24e127124a03314e35a9` (SHA-256 `393490bfefe382b9b75cf2964c131a910faa679888689457f99c2da2dc57fbbd`). Its synthetic leaf private key exists only to exercise actual signer/verifier integration; no root or intermediate private keys are present. The public-only canonical KeyUsage supplement is pinned separately (`f7b55015240951b90596692c5edec4209660a842b6f5e82e9d39da2be7c83cd1`). Expectations are external to this adapter. The two private-key availability cases are server-only and are not counted as SDK verification tests.

The implementation profile is SHA-256 `a32c6919d1f730b076994f89317ef441fa4c4b4556c093edf0216632a882f783`, with applicability profile `response-signing-public-v1`. The FFE LEAN spreadsheet remains decision authority; this implementation has no Lean proof claim.

Before merge, run `make test-ios SCHEME=DatadogFlags USE_TEST_VISIBILITY=0`, `make lint`, and `make api-surface` on the supported Xcode/macOS toolchain. Review and commit the generated API surface. Native tests cover all 46 wire cases, two KeyUsage regressions, exact transcripts, effective custom token/query binding, unsigned observation, required rejection, redirects, expiry, context/reset races, disk isolation and verified fallback retention. Linux syntax checks and explicit OpenSSL/environment-backed Swift verifier/lifecycle harnesses do not establish Apple runtime or device conformance.

The isolated certificate-rule supplement is copied byte-for-byte from
[ffe-system-test-data](https://github.com/DataDog/ffe-system-test-data/blob/b57eac6711204a906f0b24e127124a03314e35a9/response-signing/v1/isolated-certificate-rules.json)
at revision `b57eac6711204a906f0b24e127124a03314e35a9`.
Its SHA-256 is `7304bb12f011688a39b53ebd5fb5d842febd0f5ae81e67126a7e24d1e79a225a`.
The adapter checks one accepted control and three correctly signed rejections:
an oversized certificate, a leaf marked as CA, and an intermediate without CA authority.
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

## Shared precomputed response tests

The Flags module uses the JSON contract from [ffe-system-test-data](https://github.com/DataDog/ffe-system-test-data/tree/main/precomputed-assignments).
This keeps response behavior consistent across mobile SDKs. The snapshot is test data only.
It adds no runtime dependency and requires no Git submodule.

The generated snapshot is at `DatadogFlags/Tests/Fixtures/precomputed`. `SOURCE.json` records the source commit and file digests.
The runner discovers all nested JSON cases.
Adding a case requires an upstream fixture change and snapshot refresh. It requires no runner or filename-list change.
Missing or empty fixtures fail the suite. Shared `_include` and `_skip` fields describe API applicability.
Do not add local exclusions to hide failures.

Numeric behavior follows the [shared numeric contract](https://github.com/DataDog/ffe-system-test-data/blob/main/precomputed-assignments/README.md#mobile-conformance-and-numeric-types).
The native context API requires a string targeting key. Fixtures with `targetingKey: null` must declare this platform in `_skip` upstream; the runner reports an actionable fixture error if an applicable case violates that requirement.

Upstream CI requires a generated obfuscated companion for each applicable plain fixture. It rejects missing, stale, or orphaned companions. Edit the plain case upstream and regenerate; do not maintain two sets of expectations. Dedicated malformed-encoding cases and fixed digest vectors remain separate.

Cases cover values, defaults, errors, reasons, variants, emission gates, duplicate evaluations, and numeric boundaries.
Obfuscation cases cover fixed digests, salts, Unicode, whitespace, malformed metadata, and plaintext event identity.
The suite tests network decoding, serialized state, and required signature verification of the same raw responses. It checks real exposure and evaluation records. UTF-8 flag identity remains distinct during deduplication.

Run from the repository root:

```sh
python3 ci/sync-precomputed-fixtures.py --verify
xcodebuild -workspace Datadog.xcworkspace -scheme DatadogFlags -destination '<installed simulator>' -only-testing:DatadogFlagsTests/CanonicalPrecomputedTests test
```

Refresh the snapshot from a reviewed upstream commit:

```sh
python3 ci/sync-precomputed-fixtures.py --ref <full-upstream-sha>
python3 ci/sync-precomputed-fixtures.py --check
```

The importer copies committed bytes, regenerates the index, and removes deleted cases.
It preserves Unity asset GUIDs where applicable. Do not edit imported JSON or its checksums.
Use `--source <local-checkout> --ref <commit>` to test an upstream fixture branch before publication.
`--verify` checks local integrity without networking. `--check` also compares the recorded upstream commit.

The weekly `Precomputed flag fixtures` workflow opens a draft update PR when fixture content changes.
It uses a short-lived token restricted to the default branch and this workflow.
It waits when an update PR is already open. Normal SDK CI must pass before merge.
Merge the upstream fixture contract before merging its consumer PRs.
The update workflow never merges or publishes an SDK release.
