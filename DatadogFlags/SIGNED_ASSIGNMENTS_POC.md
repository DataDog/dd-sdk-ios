# Signed assignment payload POC

This branch verifies the final Feature Flags assignment payload before JSON decoding.

The SDK creates a 16-byte random nonce for each request. The edge signature binds this nonce to the request body, client token, response body, and validity period.

The verifier uses CryptoKit and Security. It trusts only the embedded POC root certificate.

The customer does not provide a key. The customer does not change the application trust store or network configuration.

The embedded root and deterministic origin key are test-only. Production must use the RC X509 root and certificate lifecycle.

## Example proof

Set `DD_SIGNED_ASSIGNMENTS_POC=1` in the Example process environment. Start the local edge service on port `17676`.

The simulator prints:

```text
Signed assignment POC result: success()
country-message: hello-us
```

`FlagAssignmentsFetcherTests.testSignedAssignmentVerifierAcceptsOriginAndRejectsTampering` verifies the saved origin fixture. It also rejects one changed response byte.
