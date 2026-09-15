# Signed assignment payload POC

Issue: FFLSDK-178

## Status

This branch contains production-shaped iOS code for the payload-integrity wargame. It is not production-approved.

The SDK verifies protected assignment bytes before it decodes or evaluates them. Protected modes never use unsigned network or persisted assignments.

The public API, certificate lifecycle, and operational telemetry still require review. The embedded root certificate is for the POC only.

## API under review

`Flags.Configuration.assignmentProtection` defines the minimum response protection that the SDK accepts.

| Mode | Request | Accepted response | Persisted state |
| --- | --- | --- | --- |
| `.disabled` | Existing request | Existing unsigned response | Existing unsigned cache only |
| `.signed` | Signature version and random nonce | Valid Datadog signature without customer authorization | Exact signed envelope with no authorization binding |
| `.signedAndAuthorized` | Signature version, random nonce, and customer JWT | Valid Datadog signature with the same JWT and policy version | Exact signed envelope bound to the current JWT digest |

The default remains `.disabled`. This keeps the feature optional for customers that do not enroll.

Supplying `assignmentAuthorization` with the default mode selects `.signedAndAuthorized`. This behavior preserves the earlier POC call site. Applications must set `assignmentProtection` explicitly when protection is required.

An incompatible explicit configuration fails safely. For example, `.signed` cannot contain assignment authorization.

### Signed-only

```swift
Flags.enable(
    with: Flags.Configuration(
        assignmentProtection: .signed
    )
)
```

### Signed and customer-authorized

```swift
let authorization = Flags.AssignmentAuthorization(
    bearerToken: cachedJWT,
    expiresAt: jwtExpiration
)

Flags.enable(
    with: Flags.Configuration(
        assignmentProtection: .signedAndAuthorized,
        assignmentAuthorization: authorization
    )
)
```

The application owns durable JWT storage and background refresh. The SDK keeps only the current JWT in memory.

Use this call after refresh:

```swift
Flags.setAssignmentAuthorization(
    .init(bearerToken: refreshedJWT, expiresAt: refreshedJWTExpiration)
)
```

Pass `nil` during logout. The SDK immediately clears protected assignments and cancels their request generation.

Authorization is scoped to the `FlagsFeature` registered in one Datadog core instance. All named `FlagsClient` instances share it.

Each named client must use the same subject and JWT. Its `targetingKey` must equal the JWT subject accepted by edge-assignments. Applications that require simultaneous subjects need separate core instances or a future client-scoped authorization API. Mobile engineers must review this public API decision.

## Protocol version 2

Protected requests use HTTPS. They do not follow redirects. They contain these control headers:

```http
x-datadog-feature-flags-signature-version: 2
x-datadog-feature-flags-request-nonce: <16 random bytes as 32 lowercase hexadecimal characters>
Authorization: Bearer <customer JWT> # signed-and-authorized only
```

Protected responses contain these headers:

```http
x-datadog-feature-flags-signature-version: 2
x-datadog-feature-flags-signing-certificate: <base64 DER leaf certificate>
x-datadog-feature-flags-certificate-id: <lowercase SHA-256 of certificate DER>
x-datadog-feature-flags-issued-at: <Unix seconds>
x-datadog-feature-flags-expires-at: <Unix seconds>
x-datadog-feature-flags-rules-revision: <verified origin revision or empty during the first wargame>
x-datadog-feature-flags-signature: <base64 DER ES256 signature>
x-datadog-feature-flags-authorization-policy-version: <policy version> # signed-and-authorized only
```

The signed transcript uses this exact order:

1. `datadog.feature-flags.precomputed-assignments.v2\0`
2. Length-prefixed HTTP method
3. Length-prefixed URL scheme
4. Length-prefixed authority
5. Length-prefixed percent-encoded path
6. Length-prefixed nonce bytes
7. SHA-256 of the exact request body
8. One authorization-presence byte
9. SHA-256 of the exact customer JWT, when present
10. SHA-256 of the Datadog client token
11. Length-prefixed authorization policy version, when authorization is present
12. Length-prefixed verified rules revision
13. Presence byte and length-prefixed value for each semantic request header
14. Response status as an unsigned 16-bit integer
15. Issue and expiration times as unsigned 64-bit integers
16. Response length as an unsigned 64-bit integer
17. SHA-256 of the exact response body

The semantic request headers are `content-type`, `dd-application-id`, `x-rkyv`, and `x-use-cache` in that order.

The iOS tests use the same signed-only and signed-and-authorized golden vectors as edge-assignments. The transcript hashes are:

- Signed-only: `b2dcfe21420f79ac6745a0e054d159d4f3197304bafb239e51c3a7aecf54f2e4`
- Signed and authorized: `b0d8cd615160a59a69a0024fdca85213b9ca6d2a542f4490706cc3d67cde3148`

## Fail-closed behavior

The SDK completes all checks before JSON decoding.

Before the SDK adds protection headers or starts the request, it validates the complete protected request. An invalid URL, body, client token, or compact JWT never reaches the network.

It rejects a protected response when any required condition is false. The checks include:

- The request uses HTTPS and has no query, fragment, or user information.
- The request uses POST and the request client-token header equals the configured client token.
- The compact customer JWT has three non-empty, unpadded base64url segments.
- The response URL equals the request URL.
- The request and response use signature protocol version 2.
- The nonce contains exactly 16 bytes.
- Signed-only contains no authorization data.
- Signed-and-authorized contains one current JWT and one policy version.
- The response includes a bounded rules revision. An empty value is valid for the first wargame.
- The certificate chains only to the embedded POC root.
- The leaf public key is a 256-bit EC key.
- The certificate ID equals the certificate digest.
- The ES256 signature covers the complete transcript.
- The response subject equals the requested `targetingKey`.
- The signature is valid now and for no more than 300 seconds.

The verifier bounds request bodies, response bodies, JWTs, client tokens, URL components, certificate headers, certificate bytes, signatures, timestamps, policy versions, and rules revisions.

Protected delivery uses a streaming `URLSessionDataDelegate`. It rejects a declared body above two MiB before body delivery. It cancels an unknown-length response when received bytes exceed two MiB. The default unprotected transport remains unchanged.

The SDK checks every Security framework configuration result. It uses the signature validation time for certificate trust evaluation.

## Persisted assignments

The cache stores the exact signed request and response bytes. It stores only the headers required to rebuild the transcript.

It also stores these scope values:

- Protection mode
- Endpoint
- Datadog environment
- Subject
- SHA-256 of the Datadog client token
- SHA-256 of the customer JWT, when used
- Authorization policy version, when used
- Certificate ID
- Rules revision
- Issue and expiration times

The cache does not store the customer JWT or Datadog client token.

On startup, the SDK rebuilds and verifies the complete signed envelope. It then compares the decoded request, response, context attributes, subject, flags, endpoint, environment, and token digests.

An expired or mismatched protected cache is deleted. Protected mode never falls back to an unsigned cache.

## Response ordering

Each context request gets a new local generation. Context changes, authorization refresh, logout, and reset also advance the generation.

A delayed success can commit only when its generation and context are still current. A delayed response cannot restore old flags after logout or reset.

## Simulator wargame

The Example app accepts these process environment values:

```text
DD_SIGNED_ASSIGNMENTS_POC=signed
FFE_STAGING_ENV=staging
FFE_STAGING_ASSIGNMENTS_ENDPOINT=https://preview.ff-cdn.datad0g.com/precompute-assignments
```

For signed-and-authorized mode, use:

```text
DD_SIGNED_ASSIGNMENTS_POC=signed-and-authorized
FFE_STAGING_ASSIGNMENT_JWT=<customer JWT>
FFE_STAGING_ASSIGNMENT_JWT_EXPIRES_AT=<JWT exp as Unix seconds>
```

The Example reads the client token through its existing `Environment.readClientToken()` path. It prints only the mode, verification result, and fixture flag value.

The Example does not support a local HTTP endpoint. Protected mode requires HTTPS.

The live XCTest uses these values:

```text
FFE_STAGING_CLIENT_TOKEN=<Datadog client token>
FFE_STAGING_PROTECTION=signed # or signed-and-authorized
FFE_STAGING_ASSIGNMENT_JWT=<customer JWT> # authorized mode only
FFE_STAGING_ENV=staging
FFE_STAGING_ASSIGNMENTS_ENDPOINT=https://preview.ff-cdn.datad0g.com/precompute-assignments
```

The test uses the production request builder and fetcher. It accepts the live response, then changes one response byte and requires rejection.

## Focused test evidence

These tests provide the main wargame evidence:

- `testSignedOnlyVerifierMatchesEdgeGoldenVector`
- `testSignedAndAuthorizedVerifierMatchesEdgeGoldenVectorAndRejectsTampering`
- `testSignedProtectionRejectsUnsignedProductionResponse`
- `testVerifierRejectsMissingOrOversizedSignedHeadersBeforeTrustEvaluation`
- `testPersistedSignedAssignmentsAreReverifiedAndBoundToContextAndClientToken`
- `testPersistedArtifactRoundTripUsesRealTrustAndRejectsCriticalFieldMutations`
- `testProtectedRequestRejectsUnsafeEndpointBeforeAddingHeadersOrFetching`
- `testSignedAndAuthorizedRequestRejectsInvalidBearerShapeBeforeNetwork`
- `testProtectedHTTPClientRejectsDeclaredOrReceivedBodiesAboveLimit`
- `testOverlappingContextUpdates_olderSuccessCannotReplaceNewerState`
- `testAuthorizationRefreshRejectsOlderProtectedSuccess`
- `testLogoutRejectsDelayedProtectedSuccess`
- `testResetRejectsDelayedProtectedSuccess`
- `testResetDuringProtectedCacheValidationDoesNotRestorePersistedState`
- `testProtectedDiskCacheValidationObservesCacheSourceAndAge`
- `testLiveStagingSignedAssignmentAndRejectsTampering`

The first two tests assert the shared edge transcript length and SHA-256. The cache tests prove certificate metadata, cache source, cache age, and generation behavior without logging sensitive values.

## Remaining production blockers

1. Mobile engineers must review the public API. The mode names and source-compatible authorization inference are not final.
2. Security engineers must approve the final root, leaf profile, key custody, rotation, overlap, revocation, and recovery procedures. The POC does not invent an assignment-signing EKU or other leaf-purpose profile.
3. The POC root and leaf are test material. Production must provision a durable Datadog Feature Flags signing hierarchy.
4. Staging must provision trusted enrollment, the signing credential, and optional customer authorization policy.
5. The live simulator test still needs staging credentials and a deployed protected route.
6. Rules revision is signed and persisted, but it does not yet prove origin integrity. Edge must receive a revision only after origin artifact verification.
7. The protected transport enforces the two-MiB body limit during delivery. Production review must still select request and resource timeouts.
8. The current client reports a safe accept or reject result. Live wargame correlation still needs an internal telemetry design for generation, certificate ID, cache source, and cache age.
9. Tests must cover the final production certificate profiles and rotation overlap. The current golden leaf expires in December 2026.
10. Feature-level authorization is shared by all named clients. Mobile API review must accept this constraint or select client-scoped authorization.

Do not use this branch as a released security claim until these blockers are complete.
