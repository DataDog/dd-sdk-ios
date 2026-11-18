# Response signing conformance fixtures

These fixtures define shared inputs and expected results for the v1 assignment
response signer and client verifiers. Consumers pin an exact repository revision
and run their native implementation against these bytes. The files are test data.
Clients do not fetch them when they evaluate flags or verify a response.

## Suites

| File | Coverage | Consumers |
| --- | --- | --- |
| `v1/corpus.json` | 77 response cases: 17 accepted and 60 rejected. 12 signer cases. | Verifiers consume `cases`. Signers also consume `signing_cases`. |
| `v1/isolated-certificate-rules.json` | An accepted control, and isolated certificate-size, leaf-CA and intermediate-CA rejections | Signers and verifiers |
| `v1/subject-der.json` | Canonical and nonminimal INTEGER encodings in the leaf subject, with valid signatures | Signers and verifiers |
| `v1/extension-profile.json` | Accepted controls, and isolated policy-mapping and empty key-identifier rejections | Signers and verifiers |
| `v1/near-expiry.json` | Four valid near-expiry proofs, a proof that outlives its leaf, and an exact-expiry rejection | Signers and verifiers |
| `v1/nested-der.json` | Canonical and noncanonical nested INTEGER encodings in a certificate extension | Signers and verifiers |

## Protocol version 1 with a certificate chain

Version 1 is the first public response-signing protocol. No public client
verified the earlier single-intermediate form of v1, so v1 changed in place to
carry a certificate chain. These names do not change:

| Name | Value |
| --- | --- |
| Signature version header value (request and response) | `1` |
| Transcript domain | `datadog.feature-flags.precomputed-assignments.v1\0` |
| Capability header value | `response-signing-v1` |
| Credential JSON `version` | `1` |

The chain contract has these rules:

- The response header `x-datadog-feature-flags-signing-chain` holds 1 to 3
  intermediate certificates. Each entry is standard base64 DER of at most 4096
  bytes. A `,` without spaces separates the entries. Index 0 issued the leaf.
  Index `i + 1` issued index `i`. The pinned root issued the last entry.
- The header `x-datadog-feature-flags-signing-intermediate` is removed. A
  response that has only this header has no chain, and a verifier rejects it.
- The transcript bytes before `SHA256(leaf)` are the same as before. The tail is
  `SHA256(leaf) || u8(n) || SHA256(int[0]) || ... || SHA256(int[n-1])`.
- The leaf extended key usage (EKU) must contain the FFE assignment-signing EKU.
  It must not contain anyExtendedKeyUsage (`2.5.29.37.0`). Other OIDs are allowed.
- Intermediate `i` must have a critical basicConstraints with cA TRUE and a
  pathLenConstraint of at least `i`. Its EKU is absent, or it contains the FFE EKU
  or anyExtendedKeyUsage.
- If the pinned root has an EKU, the EKU must contain the FFE EKU or
  anyExtendedKeyUsage. If the root has a pathLenConstraint, it must be at least `n`.
- The credential field `intermediates_der_base64` is an array of 1 to 3 strings.
  Index 0 issued the leaf. A credential with the removed `intermediate_der_base64`
  field fails to parse, and the signer does not sign.

The FFE EKU in these fixtures is the placeholder `1.3.6.1.4.1.99999.1.1`.
This arc does not belong to Datadog. Identity-core must assign the production OID
before release. Then change `FFE_EKU` in `generate-v1.py` and
`ci/verify-response-signing-vectors.py`, and regenerate all fixtures.

The corpus keeps rejection cases for the prototype version headers `2` and `3`.
It also rejects proofs signed with the abandoned draft-v3 domain and the chain
prototype v2 domain. The [single-intermediate v1 fixtures](https://github.com/DataDog/ffe-system-test-data/tree/efa1612b3a7a2217078b268af499e0dd4e8ab727/response-signing/v1)
remain available in history. Earlier validation receipts do not validate these bytes.

## Running a consumer

1. Decode `body_base64` into exact bytes. Keep header order, duplicates and URL
   escaping, because several rejection cases use these differences.
   `response.body_base64` contains application bytes after HTTP content decoding.
   When `wire_body_base64` is present, transport tests serve those compressed
   bytes with the supplied encoding headers. Direct verifier tests use `body_base64`.
2. Use the file's `anchor_der_base64` as the only trusted root. When a case has its
   own `anchor_der_base64`, use that root for that case instead. The root-profile
   cases use this override. Use `now` as Unix epoch seconds, and convert it to the
   native clock unit if necessary. Use this fixed time after the synthetic
   certificates expire too.
3. Verify each request/response pair and assert `expected_accept`. For accepted
   cases, also compare the constructed transcript with `transcript_base64`.
   `rejection_reason` is a code for the violated rule. It is not a required native
   error string.
4. Signers also load each `signing_cases` credential and the referenced response
   case. They sign that case's request and body at its `now`, with its trust
   anchor, and assert `expected_signing`. Clients do not run these cases, because
   they do not hold signing keys.

Each response carries its leaf and its chain. Verification fetches no certificate.
These fixtures cover buffered response proofs. They do not cover a signed NDJSON
protocol.

Native adapters, secret-store access, fail-open serving behavior and
implementation-specific diagnostics belong in consumer repositories. Keep these
fixtures independent of those adapters. Never derive expected results from the
implementation that you test.

## Corpus cases

Accepted cases:

- One intermediate (`valid-current`), a rotated leaf, a rotated intermediate in
  2032, an effective token with authorization, gzip transport bytes, and IPv6 with
  absent optional headers.
- Two intermediates (root, DC intermediate with pathLen 1, lower intermediate with
  pathLen 0, leaf) and three intermediates.
- A rotated lower intermediate under the same DC intermediate, with no earlier history.
- A leaf EKU with the FFE EKU and other OIDs. An intermediate EKU with the FFE EKU,
  or with anyExtendedKeyUsage. An intermediate pathLen of 1 at index 0
  (`intermediate-pathlen-one`).
- A root without pathLen (the default anchor), a root pathLen equal to the chain
  length, and a root EKU with the FFE EKU or with anyExtendedKeyUsage.
- The same lower intermediate key issued directly by the root
  (`valid-cross-issued-lower-intermediate`).

Rejected chain cases:

- Leaf EKU: codeSigning only (`leaf-wrong-eku`), another product OID only,
  FFE EKU with anyExtendedKeyUsage, and no EKU.
- Intermediate EKU without the FFE EKU or anyExtendedKeyUsage, pathLen absent,
  pathLen 0 at index 1, root pathLen below the chain length, root pathLen 0, and a
  root EKU of codeSigning only.
- Missing middle intermediate, reversed chain order, four intermediates, an empty
  entry, a trailing comma, a space after a comma, a non-base64 entry, and an entry
  over 4096 bytes.
- Only the removed `...-signing-intermediate` header, no chain header
  (`missing-intermediate`), and a duplicated chain header.
- `chain-differs-from-signed-chain`: the proof was signed for one valid chain, and
  the response carries a different valid chain. The transcript binds the chain.
- `legacy-v1-transcript-tail`: the proof was signed with the removed tail.

The other rejections cover unrelated roots, the leaf profile, expiry, changed
request or response bytes, malformed proof headers, signature tampering,
prototype versions and earlier domains. Each rejection changes one rule. The
certificate and proof signatures stay valid unless the case tests a signature.

Signer cases sign one, two and three intermediates, and a root with an FFE EKU.
Signing must fail for a mismatched private key, the legacy credential field, an
empty chain, four intermediates, a reversed chain, a missing middle intermediate,
a leaf without the FFE EKU, and a root pathLen below the chain length.

## Synthetic credentials

All certificates, identities, tokens and private keys in this suite are synthetic
test material. Each key comes from a fixed public label in the generator. The
included private keys are public, so that signer implementations can be tested.
`subject-der.json` and `extension-profile.json` reuse the corpus leaf key for the
root and the intermediate. These keys and certificates must never be trusted or
provisioned outside tests. This suite contains no production or staging
credentials and no customer responses.

## Boundary supplements

`isolated-certificate-rules.json` keeps valid certificate and response
signatures in each case. A noncritical DER OCTET STRING extension pads the
oversized leaf. The leaf-CA case keeps the leaf KeyUsage and has no path length.
The intermediate-CA case keeps the CA KeyUsage and path length zero, and omits the
CA flag. Each rejection changes only the named rule.

`subject-der.json` holds two correctly signed chains. The leaf subject contains an
attribute with OID `1.2.3.4` and INTEGER value 1. The canonical encoding is
`02 01 01`. A verifier must reject `02 02 00 01`, because the leading zero is not
necessary. A typed parser can keep this opaque attribute when it decodes and
encodes again, so equal re-encoded bytes alone are not sufficient. The root and
intermediate in this file and in `extension-profile.json` keep the corpus names,
serial numbers and key identifiers, but use the leaf key. Use each file's anchor
only for that file. Never put supplement anchors together in one trust store.

`extension-profile.json` requires rejection of policy mappings, also when they are
noncritical. When SKI or AKI is present, its identifier must not be empty. SKI and
AKI can be absent. Every rejection keeps valid certificate and proof signatures.

`nested-der.json` puts a canonical and a nonminimal INTEGER inside a noncritical
extension value. A verifier must reject the nonminimal encoding.

`near-expiry.json` uses the corpus chain. It accepts proofs when the leaf has 301,
300, 299 or 1 second left. Each accepted proof expires at
`min(issued_at + 300, leaf.not_after)`. One rejected proof extends one second past
the leaf, and is in the 300-second proof lifetime. Another rejected proof is
verified exactly when both the leaf and the proof expire.

For signer cases, assert `expected_signing` separately from `expected_accept`. A
verifier must reject the proof that outlives the leaf, but its valid credential
can still sign a new, clipped proof. For each successful signing, verify the new
proof and assert `now < expires_at <= min(now + 300, leaf.not_after)`. Do not
require the signer to choose the longest lifetime or to reproduce the fixture
signature bytes. At exact leaf expiry, signing must fail.

## Validation and regeneration

`response-signing/generate-v1.py` is the only way to regenerate these files. It
writes all six fixture files and `v1/manifest.json`. It uses only the Python
standard library. It uses fixed key labels and RFC 6979 deterministic ECDSA, so
each run writes the same bytes. The generator does not import or call an SDK,
edge or signer implementation. It sets each expectation from the protocol rules.

```sh
python3 response-signing/generate-v1.py
python3 response-signing/generate-v1.py --check
python3 ci/verify-response-signing-vectors.py
python3 -m pip install jsonschema
python3 ci/validate-response-signing.py
python3 -m unittest discover -s ci -p 'test_validate_response_signing.py'
```

`ci/verify-response-signing-vectors.py` is a separate verifier. It does not import
the generator. It has its own strict DER parser, certificate profile, chain rules,
time rules and transcript builder. It uses the `openssl` command to verify each
ECDSA signature. For each response case, it checks `expected_accept`, the
`rejection_reason` code and the transcript of accepted cases. For each signer
case, it checks `expected_signing`.

`ci/validate-response-signing.py` checks the schema, the exact file hashes, case
identities, references and counts. It allows malformed proof and certificate
fields, because negative cases use them. Structural validation does not prove
cryptographic correctness. Run native signer and verifier tests when you change
this contract.

CI checks exact regeneration, the independent verifier and manifest integrity.
Review expectation changes together with the fixtures. Do not reformat signed
body bytes or normalize headers when you import fixtures. Follow the repository's
[consumer pinning rules](../CONTRIBUTING.md#updating-downstream-repositories).
Merge fixture updates before you change downstream pins or snapshots.
