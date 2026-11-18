# Response signing v1 certificate-chain fixtures

These repo-local fixtures test the v1 certificate-chain format. They are test data only.
They are separate from the imported `ffe-system-test-data` snapshot in `../response-signing`, so `ci/sync-precomputed-fixtures.py --signing --verify` stays valid.

## Test CA credentials

A local test certificate authority issued these credentials and roots. Each JSON file holds a public synthetic leaf private key (PKCS #8 DER), the leaf certificate and `intermediates_der_base64`. Index 0 issued the leaf. `root-a.pem` and `root-b.pem` are the pinned roots.

| Credential | Chain | Expected result |
| --- | --- | --- |
| `two-intermediates` | root A, upper intermediate (pathLen 1), lower intermediate (pathLen 0), leaf with the FFE EKU | accept |
| `backup-root` | the same layout under root B | accept when root B is pinned |
| `rotated-lower-intermediate` | a new lower intermediate under the same upper intermediate | accept |
| `other-product` | leaf EKU is the product B OID only | reject (leaf EKU) |
| `missing-upper-intermediate` | lower intermediate only | reject (no pinned root issued it) |
| `one-intermediate` | root A, one intermediate (pathLen 0), leaf with the FFE EKU | accept |
| `codesigning-leaf` | root A, one intermediate, leaf with `codeSigning` only | reject (leaf EKU) |
| `unrelated-root` | a chain under a root that is not pinned | reject (no pinned root) |

The leaves are valid for 72 hours from issuance. Tests use a fixed time inside that period, so the files do not need regeneration when the leaves expire.

## Root EKU fixtures

`generate-root-eku.sh` uses OpenSSL to generate `root-eku-chain.json` and the `root-*.pem` variants. All variants have the same root key and subject, so each one can anchor the same chain. Each variant changes only one root rule:

| Root | Expected result |
| --- | --- |
| `root-eku-none` | accept (no EKU) |
| `root-eku-ffe` | accept |
| `root-eku-any` | accept (`anyExtendedKeyUsage`) |
| `root-eku-codesigning-ffe` | accept |
| `root-eku-codesigning` | reject (EKU without the FFE OID or `anyExtendedKeyUsage`) |
| `root-pathlen-0` | reject (path length is less than the number of intermediates) |

The FFE EKU OID `1.3.6.1.4.1.99999.1.1` is a placeholder. Datadog must assign the production OID before merge.
Never trust these keys or certificates outside tests.
