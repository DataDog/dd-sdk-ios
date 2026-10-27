# Evaluation telemetry control

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

Response signing is disabled by default. The browser pilot leads rollout; this native draft must pass Apple CryptoKit and simulator conformance before a protected mobile release. Signing protects accepted assignment responses against modification. It does not change subject authorization.

```swift
// publicRootDER is a locally provisioned public certificate, never response-supplied trust.
Flags.enable(with: .init(responseSigning: .init(
    mode: .observe,
    trustedRootCertificates: [publicRootDER]
)))
```

`observe` attempts verification and records a bounded outcome, then accepts otherwise-valid responses when proof is absent, invalid or expired. Authentication, HTTP, redirect and JSON errors retain their ordinary failure behavior. Observation data uses a separate cache namespace hashed from the effective token, endpoint/query, environment, app ID, custom headers, mode and root pins; it never becomes a verified cache entry. The SDK waits for the current core scope before reading that namespace and never promotes client-name-only legacy data. A separately retained verified response remains available for same-context failure fallback until its original expiry.

`required` accepts only a complete, valid v3 leaf/intermediate chain under an explicitly configured root. It never retries an unsigned request. Verified fallback is memory-only, tied to this feature instance, the complete current request configuration scope and the exact evaluation context, and expires at the original signed deadline (at most five minutes). No disk entry is trusted or written in this mode; evaluation returns defaults after expiry, a context change without a fresh response, or restart. Core context messages invalidate the old scope before further reads; reset, scope changes and superseded requests cannot restore old assignments. Stopping the SDK releases a feature-owned lifetime guard, permanently invalidating signing on retained clients and fetchers. Pending responses and later context messages cannot reactivate that instance. Configure the mode and roots when enabling Flags; replace the feature instance through the ordinary SDK lifecycle to change trust configuration.

No production root is bundled. Provision the approved public anchor before enabling verification; recovered POC roots and synthetic fixture certificates are test material only. Root trust never updates from the network. Each response carries one leaf and one intermediate so an unchanged SDK can validate later rotations without observing earlier rotations. The root is an explicit anchor outside the two-certificate path: direct CryptoKit signature checks intentionally avoid platform path-building interpretation of the recovered anchor's `pathLen=0`. The restricted DER parser enforces the shared certificate profile and never fetches issuer certificates, system roots, AIA or OCSP.

Signing-enabled requests reject redirects, use a fresh 16-byte nonce and bind the exact emitted URL/query, request body, effective client token, semantic headers, response bytes and complete public chain. Verification runs before JSON decoding and cache admission, with expiry checked again at admission and evaluation. Response verification is bounded to 2 MiB and request signing to 1 MiB. Responses are buffered application bytes after HTTP decompression; this draft does not add a signed streaming or critical-flags protocol.

For rollback during the initial pilot, keep clients in `observe` while operators disable backend signing selection, edge signing and the independent rotation controller. Those server controls stop optional proof work; they cannot remotely weaken `required` in an installed SDK. A required client falls back only within its already-verified expiry and then returns defaults. Do not start required rollout until the application owner accepts that behavior and live rotation/disable drills pass.

## Validation and shared fixtures

`Tests/Client/ResponseSigningCorpus.json` is copied byte-for-byte from the independently generated v3 corpus (SHA-256 `cc444ec8a2890430fa8dd8aee6cbde5a92d388ee55938596aac67891cfc099b6`). Its synthetic leaf private key exists only to exercise actual signer/verifier integration; no root or intermediate private keys are present. The public-only canonical KeyUsage supplement is pinned separately (`e6e2bc29ab28b490a1e17bb7c46a9342cf9496d9962c04aa5ca0e3ce6b08d347`). Expectations are external to this adapter. The two private-key availability cases are server-only and are not counted as SDK verification tests.

The implementation profile is SHA-256 `15649074caeb9a51ce233eb0d29d5725be6b33ee1c2497493f33acf992adff81`, with adapter profile `5f559ed3258045c87105b64c22df135869b0d00cdb49183e41d360b5083e1c24`. The FFE LEAN spreadsheet remains decision authority; this implementation has no Lean proof claim.

Before merge, run `make test-ios SCHEME=DatadogFlags USE_TEST_VISIBILITY=0`, `make lint`, and `make api-surface` on the supported Xcode/macOS toolchain. Review and commit the generated API surface. Native tests cover all 43 wire cases, two KeyUsage regressions, exact transcripts, effective custom token/query binding, unsigned observation, required rejection, redirects, expiry, context/reset races, disk isolation and verified fallback retention. Linux syntax checks and explicit OpenSSL/environment-backed Swift verifier/lifecycle harnesses do not establish Apple runtime or device conformance.
