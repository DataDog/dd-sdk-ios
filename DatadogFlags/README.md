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


# Response signing (experimental)

Experimental. Response signing is in preview and works only on the Datadog staging endpoint. The API can change or be removed in a minor release, based on customer feedback. The configuration property is `Flags.Configuration.experimentalResponseSigning`.

Staging only; production is not supported yet. Production support comes in a later release.

The SDK does not send `X-stream`. The edge buffers the responses that it signs. Until the edge buffering build is on staging, `required` on staging fails closed and `observe` reports `missingProof`.

The first public response-signing protocol is v1. The SDK advertises `response-signing-v1`, sends signature version `1`, and verifies the `datadog.feature-flags.precomputed-assignments.v1` transcript. A v1 response carries the leaf in `x-datadog-feature-flags-signing-certificate` and 1 to 3 intermediates in `x-datadog-feature-flags-signing-chain`. The chain header joins standard base64 DER entries with `,` and no spaces. Index 0 issued the leaf, and a pinned root issued the last entry. The SDK rejects a response that has only the earlier `x-datadog-feature-flags-signing-intermediate` header. The transcript ends with `SHA256(leaf)`, one byte with the intermediate count, and the SHA-256 digest of each intermediate in header order. Earlier POC v1/v2 and draft v3 labels are not supported public versions; public v1 does not accept their proofs. X.509 v3 certificate encoding is unchanged.

Response signing is disabled by default. It is available only for the staging assignment endpoint. `DatadogSite` has no staging case, so set `customFlagsEndpoint` to the staging endpoint. For every other endpoint, `observe` is a no-op: the SDK logs a warning, sends the ordinary request, and does not verify flags. For every other endpoint, `required` fails closed: the SDK logs an error once when Flags is enabled, sends no assignment request, puts the client in its error state, and returns `FlagsError.invalidConfiguration` on every fetch. To use Flags outside staging, remove `required` or use `observe`. Signing protects response integrity; subject authorization remains separate.

```swift
Flags.enable(with: .init(
    customFlagsEndpoint: URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments"),
    experimentalResponseSigning: .init(mode: .required)
))
```

The SDK pins one built-in anchor: `CN=Datadog Customer Signing Root CA - staging` (SHA-256 `0e469f3cecc9cd51fd64373879636540512d56e99eecd70361c78b98c47ea934`, key ID `aa5e91e52cdb130d175eed1010a501c0ef45d60d`). It applies only to `https://preview.ff-cdn.datad0g.com` on port 443.
The application's `env` value does not select a root. There is no public API to add roots, and no roots are downloaded. Tests inject their own roots through an internal initializer.
Use required mode for the staging pilot; keep production signing off. Fresh sessions provide observations across rotations without adding polling.

`observe` attempts verification and records a bounded outcome, then accepts otherwise-valid responses when proof is absent, invalid or expired. Authentication, HTTP, redirect and JSON errors retain their ordinary failure behavior. Observation data uses a separate cache namespace hashed from the effective token, endpoint/query, environment, app ID, custom headers, mode and root pins; it never becomes a verified cache entry. The SDK waits for the current core scope before reading that namespace and never promotes client-name-only legacy data. A separately retained verified response remains available for same-context failure fallback until its original expiry.

`required` accepts only a complete, valid public v1 response with a certificate chain under the pinned staging root. It never retries an unsigned request. Verified fallback is memory-only, tied to this feature instance, the complete current request configuration scope and the exact evaluation context, and expires at the original signed deadline (at most five minutes). No flag data is trusted or written to disk in this mode; evaluation returns defaults after a context change without a fresh response, or after a restart. Proof expiry depends on `expireVerifiedFlags` (see below). Core context messages invalidate the old scope before further reads; reset, scope changes and superseded requests cannot restore old assignments. Stopping the SDK releases a feature-owned lifetime guard, permanently invalidating signing on retained clients and fetchers. Pending responses and later context messages cannot reactivate that instance. Configure the mode when enabling Flags; replace the feature instance through the ordinary SDK lifecycle to change trust configuration.

The staging root remains fixed while responses carry the current leaf and intermediate certificates. The server rotates the leaf daily (previous, current and next leaves, each valid for 120 hours). The SDK never pins or caches a leaf or intermediate; any valid leaf under the root passes. An intermediate can rotate under the same parent without an SDK update. The SDK checks `notBefore <= now < notAfter` and validity nesting for every certificate, including the root. It adds no issuance freshness rule. Routine certificate rotation does not require an SDK update or a record of earlier rotations. Root validity still bounds support for unchanged SDKs. The restricted DER parser enforces the certificate profile and does not fetch issuer certificates, system roots, AIA or OCSP.

Certificate profile:

- The leaf extended key usage must contain the FFE assignment-signing OID and must not contain `anyExtendedKeyUsage`. Other OIDs are allowed.
- The intermediate at index `i` must be a CA with a decoded path length constraint of at least `i`. Its extended key usage is optional. When present, it must contain the FFE OID or `anyExtendedKeyUsage`.
- The root extended key usage is optional. When present, it must contain the FFE OID or `anyExtendedKeyUsage`. A root path length constraint must be at least the number of intermediates.
- The transcript authority is the lowercase host, with IPv6 in brackets. It contains the port only when the port is not the default port of the scheme.

The FFE OID `1.3.6.1.4.1.99999.1.1` is a placeholder. Datadog must assign the production OID before this draft is released.

Signing-enabled requests reject redirects, use a fresh 16-byte nonce and bind the exact emitted URL/query, request body, effective client token, semantic headers, response bytes and complete public chain. Verification runs before JSON decoding and cache admission, with expiry checked again at admission and evaluation. Response verification is bounded to 2 MiB and request signing to 1 MiB. Responses are buffered application bytes after HTTP decompression; this draft does not add a signed streaming or critical-flags protocol.

At signing cutover, the staging edge can serve unsigned 200 responses until the credential rotator republishes the credential. `observe` accepts such a response unverified and reports a `missingProof` outcome. `required` rejects it with `invalidResponse` and does not retry unsigned. Disabling edge signing cannot weaken `required` in an installed SDK. A required client uses verified memory only until its signed expiry, then returns defaults. Restore valid signed delivery to recover. Mobile rotation and application lifecycle validation remain required before rollout beyond staging.

## Proof expiry (`expireVerifiedFlags`)

`ResponseSigningConfiguration.expireVerifiedFlags` (default `false`) controls what `required` mode does at the `expires-at` time of the last verified proof. It has no effect in `observe` or `off` mode.

- `false` (default): the client keeps serving the last verified flags, and its state changes to `stale`. The application decides whether to refetch. A network attacker can block refreshes and keep the flags at their last verified values. The attacker cannot forge values. The guarantee is "verified once", not "fresh".
- `true`: the client state changes to `error`, and evaluations return defaults. This is the strict guarantee.

A new verified response returns the state to `ready` in both settings. The state changes at the expiry time, and again when the application reads a flag.

## Minimum not-before revocation (draft wire)

DRAFT: the edge and the shared fixtures do not send this header yet. The name and the transcript rule can change.

- A verified response can carry `x-datadog-feature-flags-minimum-not-before`: unix seconds, a decimal integer with no sign and no leading zeros, from 0 to 2^53-1, in one header line.
- When the header is present, the transcript ends with `0x01` and the value as a big-endian `u64`. When it is absent, the v1 transcript does not change. So a change, an addition or a removal of the header fails the signature.
- The SDK accepts the value only from a fully verified response. It ignores a value that is greater than the `notBefore` of any certificate in the response chain, because a response must never revoke its own chain. It reports `minimum-not-before-ignored`. It also ignores a value that is lower than the stored value.
- The SDK stores the highest value for each trust anchor (key: SHA-256 of the root DER) in the Flags feature data store, so it survives a restart. This is the only data that `required` mode persists. It holds no flag data.
- On each verification, the SDK rejects a chain if the leaf or any intermediate has a `notBefore` lower than the stored value, with the reason `revoked-certificate`. `required` fails closed. `observe` accepts the response and reports the reason. Both modes store new values.
- One value revokes all older certificates at every level below the root. To revoke an intermediate, the edge must reissue every certificate below the root that is older than the value.

## Validation and shared fixtures

`Tests/Fixtures/response-signing/SOURCE.json` pins the central repository commit and file checksums.
The native test reads every suite in the upstream manifest, checks counts and checksums,
and verifies acceptance decisions and exact transcripts. The current snapshot has 97 response
vectors across wire, nested DER, subject DER, certificate-rule, extension-profile, and expiry suites.
A case can supply its own `anchor_der_base64`, which replaces the file anchor for that case.
The test asserts only acceptance or rejection; `rejection_reason` is a fixture code, not a native error.
Server-only signing cases are excluded.
`Tests/Fixtures/response-signing-chain` holds repo-local test-CA-issued chains and OpenSSL root variants.
It is outside the imported snapshot, so the importer checks stay valid.

Refresh and verify signing fixtures with the signing importer and the weekly `Response signing fixtures` workflow:

```shell
python3 ci/sync-response-signing-fixtures.py --ref <full-upstream-sha>
python3 ci/sync-response-signing-fixtures.py --verify
python3 ci/sync-response-signing-fixtures.py --check
```

The implementation profile is SHA-256 `a32c6919d1f730b076994f89317ef441fa4c4b4556c093edf0216632a882f783`, with applicability profile `response-signing-public-v1`. The FFE LEAN spreadsheet remains decision authority; this implementation has no Lean proof claim.

Before merge, run `make test-ios SCHEME=DatadogFlags USE_TEST_VISIBILITY=0`, `make lint`, and `make api-surface` on the supported Xcode/macOS toolchain. Review and commit the generated API surface. Native tests cover all manifest-listed response cases, a noncanonical leaf KeyUsage regression, exact transcripts, effective custom token/query binding, unsigned observation, required rejection, redirects, expiry, context/reset races, disk isolation and verified fallback retention. Linux syntax checks and explicit OpenSSL/environment-backed Swift verifier/lifecycle harnesses do not establish Apple runtime or device conformance.

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
Snapshots with an opt-out policy use cache version 3, or version 4 when they also need original numeric tokens. Older SDKs that support only versions 1 or 2 cannot restore them.
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

`ci/feature-flags-precomputed-fixtures.json` pins an upstream commit. Tests read the snapshot from the git-ignored `DatadogFlags/Fixtures/precomputed` folder, outside every SwiftPM target, so fixtures never reach a customer checkout. `SOURCE.json` records the source commit and file digests.
The runner discovers all nested JSON cases.
Adding a case requires an upstream fixture change and a pin update. It requires no runner or filename-list change.
Missing or empty fixtures fail the suite. Shared `_include` and `_skip` fields describe API applicability.
Do not add local exclusions to hide failures.

Diagnostic snapshots and native bridge exports omit numeric assignments with no representable Integer or Double value.
Native typed getters still report `TYPE_MISMATCH` for these assignments. Valid zero values remain present.
Caches that require original numeric metadata use version 4. Older readers ignore these caches and must refetch assignments;
getters use application defaults until assignments become available. Other caches keep their existing versions.

Numeric behavior follows the [shared numeric contract](https://github.com/DataDog/ffe-system-test-data/blob/main/precomputed-assignments/README.md#mobile-conformance-and-numeric-types).
The native context API requires a string targeting key. Fixtures with `targetingKey: null` must declare this platform in `_skip` upstream; the runner reports an actionable fixture error if an applicable case violates that requirement.

Upstream CI requires a generated obfuscated companion for each applicable plain fixture. It rejects missing, stale, or orphaned companions. Edit the plain case upstream and regenerate; do not maintain two sets of expectations. Dedicated malformed-encoding cases and fixed digest vectors remain separate.

Cases cover values, defaults, errors, reasons, variants, emission gates, duplicate evaluations, and numeric boundaries.
Obfuscation cases cover fixed digests, salts, Unicode, whitespace, malformed metadata, and plaintext event identity.
The suite tests network decoding, serialized state, and required signature verification of the same raw responses. It checks real exposure and evaluation records. UTF-8 flag identity remains distinct during deduplication.

Run from the repository root:

```sh
make feature-flags-fixtures-pull
xcodebuild -workspace Datadog.xcworkspace -scheme DatadogFlags -destination '<installed simulator>' -only-testing:DatadogFlagsTests/CanonicalPrecomputedTests test
```

`make feature-flags-fixtures-pull` fetches the pinned commit and records file digests in `SOURCE.json`. When the local snapshot already matches the pin, it only verifies, without networking. `make test` runs it first for the `DatadogFlags` and `UnitTests-*` schemes, whose test plans include `DatadogFlagsTests`. The fetch has a time limit and retries 3 times.

Move the pin to a reviewed upstream commit:

```sh
python3 ci/sync-feature-flags-precomputed-fixtures.py --update --ref <full-upstream-sha>
```

The importer copies committed bytes, regenerates the index, and removes deleted cases.
It preserves Unity asset GUIDs where applicable. Do not edit fetched JSON or its checksums.
Use `--update --source <local-checkout> --ref <commit>` to test an upstream fixture branch before publication.
`--verify` checks that the local snapshot matches the pin without networking.

The weekly `Feature flags precomputed fixtures` workflow opens a draft update PR that proposes the latest ffe-system-test-data `main` commit.
It uses a short-lived token restricted to the default branch and this workflow.
It waits when an update PR is already open. Normal SDK CI must pass before merge.
Merge the upstream fixture contract before merging its consumer PRs.
The update workflow never merges or publishes an SDK release.

## Evaluation telemetry privacy

Evaluation telemetry is protected by default. Each event sends the targeting key as `sha256_` followed by the lowercase hex SHA-256 of its UTF-8 bytes, and omits the evaluation context. An empty targeting key is sent as an empty string. Evaluations made before any context is set have no targeting key. A targeting key that is not valid UTF-16 is omitted, and the evaluation is still counted.

The raw targeting key and the evaluation context are sent only when the flags configuration for the evaluated context enables full evaluation data. The SDK keeps that setting with the configuration it applies to, including when the configuration is restored from disk. A refresh changes later evaluations only. Events that are waiting to be sent keep the setting that applied when the flag was evaluated.

Evaluation errors are reported only as `PROVIDER_NOT_READY`, `PROVIDER_FATAL`, `FLAG_NOT_FOUND`, `PARSE_ERROR`, `TYPE_MISMATCH`, `TARGETING_KEY_MISSING`, `INVALID_CONTEXT`, or `GENERAL`. Any other error is reported as `GENERAL`.

These rules apply to evaluation telemetry only. They do not change assignment requests, targeting, or exposure events. The [evaluation telemetry control](#evaluation-telemetry-control) still suppresses evaluation telemetry for opted-out subjects.
