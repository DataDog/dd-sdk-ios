# Error Handling in dd-sdk-ios

This document covers two distinct concerns that both fall under "error handling" but must not be conflated:

1. **Customer-Facing Error Safety** — the SDK must never crash or throw into a customer's app.
2. **Internal Telemetry Error Reporting** — when the SDK reports its own internal errors to Datadog for debugging, it must never leak customer data in the process.

---

## Customer-Facing Error Safety

The SDK must **never throw exceptions** to customer code:

- **NOP implementations**: `NOPMonitor`, `NOPDatadogCore` silently accept all API calls when the SDK is not initialized or a feature is disabled.
- **Validation at boundaries**: Invalid input is logged via `DD.logger` and ignored.
- **Objective-C exception safety**: Code that can trigger an Objective-C exception outside Swift's error model (e.g. Session Replay's view-tree snapshotting in `LayerRecorder`, `ImageSnapshotter`) wraps the call with `ObjcException.rethrow`, converting it into a catchable Swift `ObjcException` (`DatadogInternal/Sources/Utils/DDError.swift`).

## Internal Telemetry Error Reporting

The SDK reports its own internal errors (encoding failures, storage corruption, unexpected state) to Datadog's internal SDK telemetry via `Telemetry.error(...)`, so engineers can debug issues in production without customer involvement. This channel is **not** customer-facing, but it is still Datadog-internal infrastructure that can — if handled carelessly — end up carrying whatever data the failing operation happened to touch (HTTP headers, encoded attribute values, decoded payloads, etc.).

**Never build a telemetry error message from an error's raw, default description.** Swift's default string interpolation of an `Error` (`"\(error)"`) is unsafe for some error types — `EncodingError.invalidValue`, for example, embeds the *entire offending value* in its description. An encoding failure on an attribute dictionary can therefore forward its raw contents (session tokens, PII, etc.) straight into telemetry.

### The safe path

- `Telemetry.error(_ error: Error, ...)` is the only entry point for reporting an `Error` to telemetry. It routes every error through `sanitizeForTelemetry(_:)` (`DatadogInternal/Sources/Telemetry/TelemetrySanitizableError.swift`) before anything reaches the wire.
- **Default behavior is anonymous**: an error that doesn't opt in is reduced to just its type name (`"\(type(of: error))"`).
- A handful of well-known Foundation/Swift types already get a safe, dedicated summary: `EncodingError`/`DecodingError` (coding path + `debugDescription` only, never the offending value), `NSError` (`domain`/`code` only, never `userInfo`, which can carry customer-supplied strings like `NSLocalizedDescriptionKey`).
- Every reported error carries a `#fileID:#line` call-site reference in `stack`, so messages stay traceable back to the reporting code even in the fully-anonymized default case.

### Opting in to richer context

A type can conform to `TelemetrySanitizableError` to describe itself more richly — but only when every piece of information exposed is known-safe:

```swift
struct FileWriteError: Error, TelemetrySanitizableError {
    let path: String
    let underlyingData: Data

    func sanitize() -> TelemetrySanitizedError {
        TelemetrySanitizedError(
            kind: "FileWriteError",
            message: "Failed to write \(underlyingData.count) bytes into \(directoryName(path))"
        )
    }
}
```

For an enum whose cases carry no associated values, or only associated values that are already known-safe (SDK-internal type/size/kind names — never customer content), `TelemetrySanitizedError(describing:)` is a shorthand for `TelemetrySanitizedError(kind: "\(type(of: error))", message: "\(error)")`:

```swift
extension TLVBlockError: TelemetrySanitizableError {
    func sanitize() -> TelemetrySanitizedError {
        TelemetrySanitizedError(describing: self)
    }
}
```

**Before conforming a type to `TelemetrySanitizableError`, audit every case and every associated value it can carry.** If a type wraps arbitrary or customer-supplied content (e.g. `WebViewMessageError`, which carries the raw WebView message body), it must **not** conform — let it fall through to the safe, anonymous default instead.

- Do not retroactively conform a type you don't own (`NSError`, `URLError`, etc.) to `TelemetrySanitizableError` — a conformance is a single, global fact about a `(Type, Protocol)` pair, so a conflicting conformance declared elsewhere would be silently discarded. For foreign types, extend `sanitizeForTelemetry(_:)` centrally instead.
- The internal `Telemetry.error(_ error: TelemetrySanitizedError, ...)` / `Telemetry.error(_ message: String, error: TelemetrySanitizedError, ...)` overloads only accept an already-sanitized error — there is no code path that can forward a raw, unsanitized error description to the sink.
